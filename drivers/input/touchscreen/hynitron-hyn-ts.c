// SPDX-License-Identifier: GPL-2.0-only
/*
 * Hynitron HYN series I2C touchscreen driver
 *
 * The register sequences and the wire protocol implemented here are taken
 * from the Hynitron vendor driver shipped with the Sipeed LicheeRV Nano BSP
 * ("== Hynitron V2.5 202406014 ==", linux_5.10/drivers/input/touchscreen/hyn/
 * in sipeed/LicheeRV-Nano-Build, GPL v2), which is the driver the vendor
 * loads for the optional MIPI touch panels: hyn_cst7xx.c for the
 * st7701_lct024bsi20 panel and hyn_cst3xx.c/hyn_cst3240.c for the
 * st7701_hd228001c31 panel.
 *
 * Only what is needed to bring the panels up is kept: chip identification,
 * boot mode entry, touch reporting, interrupt handling and system
 * suspend/resume.  The vendor firmware update, gesture, proximity and debug
 * filesystem interfaces are not implemented; the panels do not use them.
 *
 * Copyright (c) 2019-2024 Hynitron Driver Team
 */

#include <linux/bits.h>
#include <linux/delay.h>
#include <linux/device.h>
#include <linux/err.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/input.h>
#include <linux/input/mt.h>
#include <linux/input/touchscreen.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/pm.h>
#include <linux/property.h>
#include <linux/unaligned.h>

#define HYN_CST3XX_MAX_POINTS		5
#define HYN_CST3240_MAX_POINTS		5
#define HYN_CST7XX_MAX_POINTS		2

/* Coordinate width of the self-capacitance parts: 12 bit. */
#define HYN_CST7XX_COORD_MAX		0x0fff

/*
 * Mutual capacitance report block (CST3xx and CST3240): a frame starts at
 * 0xd000 with the first touch point, the touch count (bit 7 marks a touch
 * key frame) and a 0xab check byte.  Further points live at 0xd007, and the
 * read is acknowledged by writing 0xd000 = 0xab.
 */
#define CST3XX_TOUCH_REG		0x00d000
#define CST3XX_TOUCH_MORE_REG		0x00d007
#define CST3XX_TOUCH_ACK		0x00d000ab
#define CST3XX_TOUCH_CHK_VAL		0xab
#define CST3XX_TOUCH_COUNT_MASK		GENMASK(6, 0)
#define CST3XX_TOUCH_KEY_BIT		BIT(7)
#define CST3XX_TOUCH_EVENT_MASK		GENMASK(3, 1)
#define CST3XX_TOUCH_EVENT_DOWN		0x06

/* Bootloader handshake shared by CST3xx and CST3240 (same slave address). */
#define CST3XX_BOOT_PROG_CMD		0x00a001aa
#define CST3XX_BOOT_CHK_REG		0x00a002
#define CST3XX_BOOT_CHK_VAL		0x55
#define HYN_BOOT_STATUS_REG		0x00a000
#define HYN_BOOT_STATUS_OK		0x01
#define HYN_BOOT_CSUM_REG		0x00a008

/* CST3xx application mode. */
#define CST3XX_INFO_CMD			0x00d101
#define CST3XX_INFO_REG			0x00d1f4
#define CST3XX_MODE_NORMAL		0x00d100
#define CST3XX_MODE_SLEEP		0x00d105

/* CST3240 application mode. */
#define CST3240_BOOT_EXIT_CMD		0x00a00100
#define CST3240_BOOT_CHK_VAL0		0x55
#define CST3240_BOOT_CHK_VAL1		0xa8
#define CST3240_CHIP_TYPE		0x3240
#define CST3240_INFO_CMD		0x00d101
#define CST3240_INFO_REG		0x00d204
#define CST3240_INFO_REG2		0x00d1f4
#define CST3240_MODE_NORMAL		0x00d109

/* Self capacitance parts: 1 byte register, 0x6a in boot mode. */
#define CST7XX_BOOT_ADDR		0x6a
#define CST7XX_BOOT_PROG_CMD		0x00a001aa
#define CST7XX_BOOT_CHK_REG		0x00a003
#define CST7XX_BOOT_CHK_VAL		0x55
#define CST7XX_BOOT_CSUM_CMD		0x00a00300
#define CST7XX_BOOT_CSUM_REG		0x00a008
#define CST7XX_BOOT_EXIT_CMD		0x00a006ee
#define CST7XX_INFO_REG			0xa7
#define CST7XX_TOUCH_REG		0x00
#define CST7XX_TOUCH_UP_BIT		BIT(6)
#define CST7XX_MODE_NORMAL		0xfe00
#define CST7XX_MODE_SLEEP		0xa503

struct hyn_ts;

struct hyn_chip_data {
	const char *name;
	unsigned int max_touch_num;
	/* Fixed slave the controller answers to. */
	u8 main_addr;
	/* Slave address used while the part is in boot mode, 0 if unchanged. */
	u8 boot_addr;
	int (*init)(struct hyn_ts *ts);
	void (*report)(struct hyn_ts *ts);
	int (*suspend)(struct hyn_ts *ts);
	int (*resume)(struct hyn_ts *ts);
};

struct hyn_ts {
	struct i2c_client *client;
	struct input_dev *input;
	struct gpio_desc *reset_gpio;
	const struct hyn_chip_data *chip;
	struct touchscreen_properties prop;
	u16 x_res;
	u16 y_res;
};

static int hyn_xfer(struct hyn_ts *ts, u16 addr, const u8 *wbuf, size_t wlen,
		    u8 *rbuf, size_t rlen)
{
	struct i2c_msg msgs[2];
	int n = 0;
	int ret;

	msgs[n++] = (struct i2c_msg){
		.addr = addr,
		.flags = 0,
		.len = (u16)wlen,
		.buf = (u8 *)wbuf,
	};

	if (rlen)
		msgs[n++] = (struct i2c_msg){
			.addr = addr,
			.flags = I2C_M_RD,
			.len = (u16)rlen,
			.buf = rbuf,
		};

	ret = i2c_transfer(ts->client->adapter, msgs, n);
	if (ret != n)
		return ret < 0 ? ret : -EIO;

	return 0;
}

/* The register address is sent big endian first, data follows. */
static void hyn_reg_encode(u8 *buf, u32 reg, unsigned int reg_len)
{
	unsigned int i;

	for (i = 0; i < reg_len; i++)
		buf[i] = reg >> (8 * (reg_len - 1 - i));
}

static int hyn_write_addr(struct hyn_ts *ts, u16 addr, u32 reg,
			  unsigned int reg_len)
{
	u8 buf[4];

	hyn_reg_encode(buf, reg, reg_len);

	return hyn_xfer(ts, addr, buf, reg_len, NULL, 0);
}

static int hyn_read_addr(struct hyn_ts *ts, u16 addr, u32 reg,
			 unsigned int reg_len, void *val, size_t len)
{
	u8 buf[4];

	hyn_reg_encode(buf, reg, reg_len);

	return hyn_xfer(ts, addr, buf, reg_len, val, len);
}

static u16 hyn_boot_addr(struct hyn_ts *ts)
{
	return ts->chip->boot_addr ? ts->chip->boot_addr : ts->client->addr;
}

static int hyn_write(struct hyn_ts *ts, u32 reg, unsigned int reg_len)
{
	return hyn_write_addr(ts, ts->client->addr, reg, reg_len);
}

static int hyn_read(struct hyn_ts *ts, u32 reg, unsigned int reg_len,
		    void *val, size_t len)
{
	return hyn_read_addr(ts, ts->client->addr, reg, reg_len, val, len);
}

/*
 * The reset line is active low and left deasserted in normal operation, as
 * described by the vendor driver.
 */
static void hyn_reset(struct hyn_ts *ts, unsigned int delay_ms)
{
	gpiod_set_value_cansleep(ts->reset_gpio, 1);
	usleep_range(5000, 6000);
	gpiod_set_value_cansleep(ts->reset_gpio, 0);
	if (delay_ms)
		msleep(delay_ms);
}

static void hyn_release_all(struct hyn_ts *ts)
{
	input_mt_report_pointer_emulation(ts->input, true);
	input_mt_sync_frame(ts->input);
	input_sync(ts->input);
}

/* Mutual capacitance parts (CST3xx, CST3240). */

static int hyn_cst3xx_read_frame(struct hyn_ts *ts, u8 *buf,
				 unsigned int *count)
{
	int ret;

	ret = hyn_read(ts, CST3XX_TOUCH_REG, 2, buf, 7);
	if (ret)
		return ret;

	if (buf[6] != CST3XX_TOUCH_CHK_VAL || buf[0] == CST3XX_TOUCH_CHK_VAL)
		return -EBADMSG;

	*count = buf[5] & CST3XX_TOUCH_COUNT_MASK;
	if (*count > ts->chip->max_touch_num)
		return -EBADMSG;

	/* None of the supported panels has touch keys below the display. */
	if (buf[5] & CST3XX_TOUCH_KEY_BIT)
		return -EOPNOTSUPP;

	if (*count > 1) {
		ret = hyn_read(ts, CST3XX_TOUCH_MORE_REG, 2, &buf[5],
			       (*count - 1) * 5 + 1);
		if (ret)
			return ret;
	}

	return 0;
}

static void hyn_cst3xx_report(struct hyn_ts *ts)
{
	struct device *dev = &ts->client->dev;
	u8 buf[3 + 5 * HYN_CST3XX_MAX_POINTS];
	unsigned int count, i;
	int ret;

	ret = hyn_cst3xx_read_frame(ts, buf, &count);
	if (ret) {
		if (ret == -EOPNOTSUPP)
			dev_dbg_ratelimited(dev, "touch key frame ignored\n");
		else
			dev_err_ratelimited(dev, "failed to read touch data: %d\n",
					    ret);
		goto ack;
	}

	for (i = 0; i < count; i++) {
		const u8 *p = &buf[i * 5];
		unsigned int id = p[0] >> 4;
		unsigned int x = (p[1] << 4) | (p[3] >> 4);
		unsigned int y = (p[2] << 4) | (p[3] & 0x0f);

		if ((p[0] & CST3XX_TOUCH_EVENT_MASK) != CST3XX_TOUCH_EVENT_DOWN)
			continue;
		if (id >= ts->chip->max_touch_num)
			continue;

		input_mt_slot(ts->input, id);
		input_mt_report_slot_state(ts->input, MT_TOOL_FINGER, true);
		touchscreen_report_pos(ts->input, &ts->prop, x, y, true);
		input_report_abs(ts->input, ABS_MT_TOUCH_MAJOR, p[4] >> 3);
	}

	hyn_release_all(ts);

ack:
	/* Acknowledge the frame so the controller can latch the next one. */
	if (hyn_write(ts, CST3XX_TOUCH_ACK, 3))
		dev_err_ratelimited(dev, "failed to acknowledge touch frame\n");
}

static int hyn_cst3xx_boot_enter(struct hyn_ts *ts)
{
	struct device *dev = &ts->client->dev;
	u8 val;
	int ret, retry;

	for (retry = 0; retry < 5; retry++) {
		hyn_reset(ts, 6 + retry);
		ret = hyn_write_addr(ts, hyn_boot_addr(ts),
				     CST3XX_BOOT_PROG_CMD, 3);
		if (ret)
			continue;
		ret = hyn_read_addr(ts, hyn_boot_addr(ts),
				    CST3XX_BOOT_CHK_REG, 2, &val, 1);
		if (!ret && val == CST3XX_BOOT_CHK_VAL)
			return 0;
	}

	return dev_err_probe(dev, -ENODEV, "failed to enter bootloader mode\n");
}

static int hyn_cst3xx_init(struct hyn_ts *ts)
{
	struct device *dev = &ts->client->dev;
	u8 buf[28], status;
	u32 checksum = 0;
	int ret;

	ret = hyn_cst3xx_boot_enter(ts);
	if (ret)
		return ret;

	ret = hyn_read(ts, HYN_BOOT_STATUS_REG, 2, &status, 1);
	if (!ret && status == HYN_BOOT_STATUS_OK) {
		ret = hyn_read(ts, HYN_BOOT_CSUM_REG, 2, buf, 4);
		if (!ret)
			checksum = get_unaligned_le32(buf);
	}

	/* Back to the application firmware. */
	hyn_reset(ts, 50);

	ret = hyn_write(ts, CST3XX_INFO_CMD, 2);
	if (ret)
		return ret;

	/* The part needs a moment to latch the information block. */
	usleep_range(1000, 2000);

	ret = hyn_read(ts, CST3XX_INFO_REG, 2, buf, sizeof(buf));
	if (ret)
		return ret;

	ts->x_res = get_unaligned_le16(&buf[4]);
	ts->y_res = get_unaligned_le16(&buf[6]);

	dev_info(dev, "CST3xx: %ux%u, %u/%u sensors, chip 0x%04x, proj 0x%04x, fw 0x%08x, csum 0x%08x\n",
		 ts->x_res, ts->y_res, buf[0], buf[2],
		 get_unaligned_le16(&buf[18]), get_unaligned_le16(&buf[16]),
		 get_unaligned_le32(&buf[20]), checksum);

	return hyn_write(ts, CST3XX_MODE_NORMAL, 2);
}

static int hyn_cst3xx_suspend(struct hyn_ts *ts)
{
	return hyn_write(ts, CST3XX_MODE_SLEEP, 2);
}

static int hyn_cst3xx_resume(struct hyn_ts *ts)
{
	hyn_reset(ts, 50);

	return hyn_write(ts, CST3XX_MODE_NORMAL, 2);
}

/* CST3240: same report block, different identification and mode commands. */

static int hyn_cst3240_init(struct hyn_ts *ts)
{
	struct device *dev = &ts->client->dev;
	u8 info[16], status;
	u32 checksum = 0;
	unsigned int retry, i, type;
	int ret;

	for (retry = 0; retry < 20; retry++) {
		hyn_reset(ts, 5 + retry);
		ret = hyn_write(ts, CST3XX_BOOT_PROG_CMD, 3);
		if (ret)
			continue;

		for (i = 0; i < 4; i++) {
			ret = hyn_read(ts, CST3XX_BOOT_CHK_REG, 2, info, 2);
			if (!ret && info[0] == CST3240_BOOT_CHK_VAL0 &&
			    info[1] == CST3240_BOOT_CHK_VAL1)
				break;
			usleep_range(1000, 2000);
		}
		if (i == 4)
			continue;

		ret = hyn_write(ts, CST3240_BOOT_EXIT_CMD, 3);
		if (ret)
			continue;

		break;
	}

	if (retry == 20)
		return dev_err_probe(dev, -ENODEV,
				     "failed to enter bootloader mode\n");

	ret = hyn_read(ts, HYN_BOOT_STATUS_REG, 2, &status, 1);
	if (!ret && status == HYN_BOOT_STATUS_OK) {
		ret = hyn_read(ts, HYN_BOOT_CSUM_REG, 2, info, 4);
		if (!ret)
			checksum = get_unaligned_le32(info);
	}

	hyn_reset(ts, 50);

	ret = hyn_write(ts, CST3240_INFO_CMD, 2);
	if (ret)
		return ret;

	ret = hyn_read(ts, CST3240_INFO_REG, 2, info, 8);
	if (ret)
		return ret;

	type = get_unaligned_le16(&info[2]);
	if (type != CST3240_CHIP_TYPE)
		return dev_err_probe(dev, -ENODEV,
				     "chip type 0x%04x, expected 0x%04x; a different Hynitron part needs its own compatible\n",
				     type, CST3240_CHIP_TYPE);

	ret = hyn_read(ts, CST3240_INFO_REG2, 2, &info[8], 8);
	if (ret)
		return ret;

	ts->x_res = get_unaligned_le16(&info[12]);
	ts->y_res = get_unaligned_le16(&info[14]);

	dev_info(dev, "CST3240: %ux%u, %u/%u sensors, proj 0x%04x, fw 0x%08x, csum 0x%08x\n",
		 ts->x_res, ts->y_res, info[8], info[10],
		 get_unaligned_le16(&info[0]), get_unaligned_le32(&info[4]),
		 checksum);

	return hyn_write(ts, CST3240_MODE_NORMAL, 2);
}

static int hyn_cst3240_suspend(struct hyn_ts *ts)
{
	return hyn_write(ts, CST3XX_MODE_SLEEP, 2);
}

static int hyn_cst3240_resume(struct hyn_ts *ts)
{
	hyn_reset(ts, 50);

	return hyn_write(ts, CST3240_MODE_NORMAL, 2);
}

/* Self capacitance parts (CST7xx). */

static void hyn_cst7xx_report(struct hyn_ts *ts)
{
	struct device *dev = &ts->client->dev;
	u8 buf[3 + 6 * HYN_CST7XX_MAX_POINTS];
	unsigned int count, i;
	int ret;

	ret = hyn_read(ts, CST7XX_TOUCH_REG, 1, buf, sizeof(buf));
	if (ret) {
		dev_err_ratelimited(dev, "failed to read touch data: %d\n", ret);
		return;
	}

	count = buf[2];
	if (count > HYN_CST7XX_MAX_POINTS)
		count = HYN_CST7XX_MAX_POINTS;

	for (i = 0; i < count; i++) {
		const u8 *p = &buf[3 + i * 6];
		unsigned int id = p[2] >> 4;
		unsigned int x = ((p[0] & 0x0f) << 8) | p[1];
		unsigned int y = ((p[2] & 0x0f) << 8) | p[3];

		if (p[0] & CST7XX_TOUCH_UP_BIT)
			continue;
		if (id >= ts->chip->max_touch_num)
			continue;

		input_mt_slot(ts->input, id);
		input_mt_report_slot_state(ts->input, MT_TOOL_FINGER, true);
		touchscreen_report_pos(ts->input, &ts->prop, x, y, true);
	}

	hyn_release_all(ts);
}

static int hyn_cst7xx_init(struct hyn_ts *ts)
{
	struct device *dev = &ts->client->dev;
	u16 addr = CST7XX_BOOT_ADDR;
	u8 val = 0, buf[4];
	u32 checksum = 0;
	unsigned int retry, i;
	int ret;

	for (retry = 5; retry < 15; retry += 2) {
		hyn_reset(ts, retry);
		ret = hyn_write_addr(ts, addr, CST7XX_BOOT_PROG_CMD, 3);
		if (ret)
			continue;
		ret = hyn_read_addr(ts, addr, CST7XX_BOOT_CHK_REG, 2, &val, 1);
		if (!ret && val == CST7XX_BOOT_CHK_VAL)
			break;
	}

	if (retry >= 15)
		return dev_err_probe(dev, -ENODEV,
				     "failed to enter bootloader mode\n");

	/* Ask the bootloader to checksum the application firmware. */
	ret = hyn_write_addr(ts, addr, CST7XX_BOOT_CSUM_CMD, 3);
	if (ret)
		return ret;

	msleep(100);

	for (i = 0; i < 100; i++) {
		ret = hyn_read_addr(ts, addr, HYN_BOOT_STATUS_REG, 2, &val, 1);
		if (!ret && (val == 1 || val == 2))
			break;
		usleep_range(10000, 11000);
	}

	if (val == 1) {
		ret = hyn_read_addr(ts, addr, CST7XX_BOOT_CSUM_REG, 2, buf, 2);
		if (!ret)
			checksum = get_unaligned_le16(buf);
	}

	ret = hyn_write_addr(ts, addr, CST7XX_BOOT_EXIT_CMD, 3);
	if (ret)
		return ret;

	/* Back to the application firmware, at the address in the DT. */
	hyn_reset(ts, 50);

	ret = hyn_read(ts, CST7XX_INFO_REG, 1, buf, sizeof(buf));
	if (ret)
		return ret;

	dev_info(dev, "CST7xx: chip 0x%02x, proj 0x%02x, fw 0x%02x, csum 0x%04x\n",
		 buf[0], buf[1], buf[2], checksum);

	return hyn_write(ts, CST7XX_MODE_NORMAL, 2);
}

static int hyn_cst7xx_suspend(struct hyn_ts *ts)
{
	return hyn_write(ts, CST7XX_MODE_SLEEP, 2);
}

static int hyn_cst7xx_resume(struct hyn_ts *ts)
{
	hyn_reset(ts, 50);

	return hyn_write(ts, CST7XX_MODE_NORMAL, 2);
}

static int hyn_input_init(struct hyn_ts *ts)
{
	struct device *dev = &ts->client->dev;
	struct input_dev *input;
	unsigned int max_x = HYN_CST7XX_COORD_MAX, max_y = HYN_CST7XX_COORD_MAX;
	int ret;

	input = devm_input_allocate_device(dev);
	if (!input)
		return -ENOMEM;

	input->name = devm_kasprintf(dev, GFP_KERNEL, "Hynitron %s Touchscreen",
				     ts->chip->name);
	if (!input->name)
		return -ENOMEM;

	input->phys = "input/ts";
	input->id.bustype = BUS_I2C;
	input_set_drvdata(input, ts);

	if (ts->x_res && ts->y_res) {
		max_x = ts->x_res - 1;
		max_y = ts->y_res - 1;
	} else if (!device_property_present(dev, "touchscreen-size-x") ||
		   !device_property_present(dev, "touchscreen-size-y")) {
		dev_warn(dev, "touchscreen-size-x/y not specified, using the controller coordinate space\n");
	}

	input_set_abs_params(input, ABS_MT_POSITION_X, 0, max_x, 0, 0);
	input_set_abs_params(input, ABS_MT_POSITION_Y, 0, max_y, 0, 0);
	input_set_abs_params(input, ABS_MT_TOUCH_MAJOR, 0, 255, 0, 0);
	input_set_capability(input, EV_KEY, BTN_TOUCH);

	touchscreen_parse_properties(input, true, &ts->prop);

	ret = input_mt_init_slots(input, ts->chip->max_touch_num,
				  INPUT_MT_DIRECT | INPUT_MT_DROP_UNUSED);
	if (ret) {
		dev_err(dev, "failed to initialize MT slots: %d\n", ret);
		return ret;
	}

	ret = input_register_device(input);
	if (ret) {
		dev_err(dev, "failed to register input device: %d\n", ret);
		return ret;
	}

	ts->input = input;

	return 0;
}

static irqreturn_t hyn_irq(int irq, void *data)
{
	struct hyn_ts *ts = data;

	ts->chip->report(ts);

	return IRQ_HANDLED;
}

static int hyn_suspend(struct device *dev)
{
	struct hyn_ts *ts = dev_get_drvdata(dev);
	int ret;

	disable_irq(ts->client->irq);
	hyn_release_all(ts);

	ret = ts->chip->suspend(ts);
	if (ret) {
		dev_err(dev, "failed to suspend the controller: %d\n", ret);
		enable_irq(ts->client->irq);
	}

	return ret;
}

static int hyn_resume(struct device *dev)
{
	struct hyn_ts *ts = dev_get_drvdata(dev);
	int ret;

	ret = ts->chip->resume(ts);

	hyn_release_all(ts);
	enable_irq(ts->client->irq);

	if (ret)
		dev_err(dev, "failed to resume the controller: %d\n", ret);

	return ret;
}

static DEFINE_SIMPLE_DEV_PM_OPS(hyn_pm_ops, hyn_suspend, hyn_resume);

static int hyn_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct hyn_ts *ts;
	int ret;

	ts = devm_kzalloc(dev, sizeof(*ts), GFP_KERNEL);
	if (!ts)
		return -ENOMEM;

	ts->client = client;
	ts->chip = i2c_get_match_data(client);
	if (!ts->chip)
		return dev_err_probe(dev, -ENODEV, "unsupported device\n");

	i2c_set_clientdata(client, ts);

	if (client->addr != ts->chip->main_addr)
		return dev_err_probe(dev, -ENODEV,
				     "%s answers at I2C address 0x%02x, not 0x%02x\n",
				     ts->chip->name, ts->chip->main_addr,
				     client->addr);

	if (client->irq <= 0)
		return dev_err_probe(dev, -EINVAL, "no interrupt specified\n");

	ts->reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(ts->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(ts->reset_gpio),
				     "failed to get the reset gpio\n");

	ret = ts->chip->init(ts);
	if (ret)
		return ret;

	ret = hyn_input_init(ts);
	if (ret)
		return ret;

	ret = devm_request_threaded_irq(dev, client->irq, NULL, hyn_irq,
					IRQF_ONESHOT, dev_driver_string(dev), ts);
	if (ret)
		return dev_err_probe(dev, ret, "failed to request the interrupt\n");

	dev_info(dev, "%s touchscreen ready\n", ts->chip->name);

	return 0;
}

static const struct hyn_chip_data hyn_cst3xx_data = {
	.name = "CST3xx",
	.max_touch_num = HYN_CST3XX_MAX_POINTS,
	.main_addr = 0x1a,
	.init = hyn_cst3xx_init,
	.report = hyn_cst3xx_report,
	.suspend = hyn_cst3xx_suspend,
	.resume = hyn_cst3xx_resume,
};

static const struct hyn_chip_data hyn_cst3240_data = {
	.name = "CST3240",
	.max_touch_num = HYN_CST3240_MAX_POINTS,
	.main_addr = 0x5a,
	.init = hyn_cst3240_init,
	.report = hyn_cst3xx_report,
	.suspend = hyn_cst3240_suspend,
	.resume = hyn_cst3240_resume,
};

static const struct hyn_chip_data hyn_cst7xx_data = {
	.name = "CST7xx",
	.max_touch_num = HYN_CST7XX_MAX_POINTS,
	.main_addr = 0x15,
	.boot_addr = CST7XX_BOOT_ADDR,
	.init = hyn_cst7xx_init,
	.report = hyn_cst7xx_report,
	.suspend = hyn_cst7xx_suspend,
	.resume = hyn_cst7xx_resume,
};

static const struct i2c_device_id hyn_id[] = {
	{ .name = "hyn_ts" },
	{ }
};
MODULE_DEVICE_TABLE(i2c, hyn_id);

static const struct of_device_id hyn_of_match[] = {
	{ .compatible = "hyn,3xx", .data = &hyn_cst3xx_data },
	{ .compatible = "hyn,3240", .data = &hyn_cst3240_data },
	{ .compatible = "hyn,7xx", .data = &hyn_cst7xx_data },
	{ }
};
MODULE_DEVICE_TABLE(of, hyn_of_match);

static struct i2c_driver hyn_driver = {
	.driver = {
		.name = "hynitron-hyn-ts",
		.of_match_table = hyn_of_match,
		.pm = pm_ptr(&hyn_pm_ops),
		.probe_type = PROBE_PREFER_ASYNCHRONOUS,
	},
	.probe = hyn_probe,
	.id_table = hyn_id,
};
module_i2c_driver(hyn_driver);

MODULE_AUTHOR("Hynitron Driver Team");
MODULE_DESCRIPTION("Hynitron HYN series touchscreen driver");
MODULE_LICENSE("GPL");
