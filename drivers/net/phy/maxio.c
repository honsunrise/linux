// SPDX-License-Identifier: GPL-2.0-or-later
/* Driver for Maxio Ethernet PHYs. */

#include <linux/delay.h>
#include <linux/module.h>
#include <linux/phy.h>

#define MAXIO_PAGE_SELECT		0x1f

#define MAXIO_MAE0621A_LED_PAGE		0x0d04
#define MAXIO_MAE0621A_LED_CTRL_REG	0x10
#define MAXIO_MAE0621A_EEE_LED_CTRL_REG	0x11
#define MAXIO_MAE0621A_LED_CTRL_SET	(BIT(5) | BIT(8) | BIT(10) | BIT(11))
#define MAXIO_MAE0621A_LED_CTRL_CLEAR	BIT(14)
#define MAXIO_MAE0621A_EEE_LED_EN	BIT(3)
#define MAXIO_MAE0621A_EEE_PAGE		0x0a4b
#define MAXIO_MAE0621A_EEE_CTRL_REG	0x11

#define MAXIO_PHYSR_PAGE		0x0a43
#define MAXIO_PHYSR_REG			0x1a
#define MAXIO_PHY_DUPLEX		BIT(3)
#define MAXIO_PHY_SPEED			GENMASK(5, 4)
#define MAXIO_PHY_SPEED_1000		BIT(5)
#define MAXIO_PHY_SPEED_100		BIT(4)
#define MAXIO_PHY_SPEED_10		0

#define MAXIO_AN_INT_PAGE		0x0a42
#define MAXIO_AN_INT_ENABLE_REG		0x12
#define MAXIO_AN_COMPLETE_INT_ENABLE	BIT(3)
#define MAXIO_AN_STATUS_PAGE		0x0a43
#define MAXIO_AN_STATUS_REG		0x1d
#define MAXIO_AN_COMPLETE		BIT(3)
#define MAXIO_LINK_OK			BIT(2)
#define MAXIO_AN_MAX_RETRIES		4

struct maxio_priv {
	unsigned int an_retries;
	bool link_stable;
};

struct maxio_reg_write {
	u16 page;
	u16 reg;
	u16 val;
};

static int maxio_read_page(struct phy_device *phydev)
{
	return __phy_read(phydev, MAXIO_PAGE_SELECT);
}

static int maxio_write_page(struct phy_device *phydev, int page)
{
	return __phy_write(phydev, MAXIO_PAGE_SELECT, page);
}

static int maxio_write_sequence(struct phy_device *phydev,
				const struct maxio_reg_write *sequence,
				size_t count)
{
	int ret;

	for (size_t i = 0; i < count; i++) {
		ret = phy_write_paged(phydev, sequence[i].page,
				      sequence[i].reg, sequence[i].val);
		if (ret)
			return ret;
	}

	return 0;
}

static int maxio_mae0621a_led_config(struct phy_device *phydev)
{
	int ret;

	ret = phy_modify_paged(phydev, MAXIO_MAE0621A_LED_PAGE,
			       MAXIO_MAE0621A_LED_CTRL_REG,
			       MAXIO_MAE0621A_LED_CTRL_SET |
			       MAXIO_MAE0621A_LED_CTRL_CLEAR,
			       MAXIO_MAE0621A_LED_CTRL_SET);
	if (ret)
		return ret;

	return phy_modify_paged(phydev, MAXIO_MAE0621A_LED_PAGE,
				MAXIO_MAE0621A_EEE_LED_CTRL_REG,
				MAXIO_MAE0621A_EEE_LED_EN, 0);
}

static int maxio_mae0621a_eee_config(struct phy_device *phydev)
{
	static const struct maxio_reg_write sequence[] = {
		{ MAXIO_MAE0621A_EEE_PAGE, MAXIO_MAE0621A_EEE_CTRL_REG, 0x1110 },
		{ 0, MII_MMD_CTRL, MDIO_MMD_AN },
		{ 0, MII_MMD_DATA, MDIO_AN_EEE_ADV },
		{ 0, MII_MMD_CTRL, MDIO_MMD_AN | MII_MMD_CTRL_NOINCR },
		{ 0, MII_MMD_DATA, 0 },
	};
	int ret;

	ret = phy_write(phydev, MAXIO_PAGE_SELECT, 0);
	if (ret)
		return ret;

	ret = phy_write(phydev, MII_BMCR, BMCR_RESET);
	if (ret)
		return ret;

	msleep(20);

	return maxio_write_sequence(phydev, sequence, ARRAY_SIZE(sequence));
}

static int maxio_adcc_check(struct phy_device *phydev)
{
	int adc_value;
	int ret;

	ret = phy_write_paged(phydev, 0x0d96, 0x02, 0x1fff);
	if (ret)
		return ret;

	ret = phy_write_paged(phydev, 0x0d96, 0x02, 0x1000);
	if (ret)
		return ret;

	for (unsigned int i = 0; i < 4; i++) {
		ret = phy_write_paged(phydev, 0x0d8f, 0x0b,
				      0xf908 + i * 0x100);
		if (ret)
			return ret;

		adc_value = phy_read_paged(phydev, 0x0d92, 0x0b);
		if (adc_value < 0)
			return adc_value;
		if (!(adc_value & 0x1ff))
			return -EIO;
	}

	return 0;
}

static int maxio_self_check(struct phy_device *phydev, unsigned int attempts)
{
	static const struct maxio_reg_write retry_sequence[] = {
		{ 0, MII_BMCR, 0x1940 },
		{ 0, MII_BMCR, 0x1140 },
		{ 0, MII_BMCR, 0x9140 },
	};
	static const struct maxio_reg_write finish_sequence[] = {
		{ 0x0d96, 0x02, 0x0fff },
		{ 0, MII_BMCR, 0x9140 },
	};
	int ret = -EIO;

	for (unsigned int i = 0; i < attempts; i++) {
		ret = maxio_adcc_check(phydev);
		if (!ret) {
			phydev_dbg(phydev, "analog self-check passed\n");
			break;
		}

		ret = maxio_write_sequence(phydev, retry_sequence,
					   ARRAY_SIZE(retry_sequence));
		if (ret)
			break;

		usleep_range(10000, 11000);
	}

	if (maxio_write_sequence(phydev, finish_sequence,
				 ARRAY_SIZE(finish_sequence)) && !ret)
		ret = -EIO;

	return ret;
}

static int maxio_resolve_aneg_linkmode(struct phy_device *phydev)
{
	int phy_status;

	phy_status = phy_read_paged(phydev, MAXIO_PHYSR_PAGE, MAXIO_PHYSR_REG);
	if (phy_status < 0)
		return phy_status;

	switch (phy_status & MAXIO_PHY_SPEED) {
	case MAXIO_PHY_SPEED_1000:
		phydev->speed = SPEED_1000;
		break;
	case MAXIO_PHY_SPEED_100:
		phydev->speed = SPEED_100;
		break;
	case MAXIO_PHY_SPEED_10:
		phydev->speed = SPEED_10;
		break;
	default:
		phydev->speed = SPEED_UNKNOWN;
		break;
	}

	phydev->duplex = phy_status & MAXIO_PHY_DUPLEX ?
			 DUPLEX_FULL : DUPLEX_HALF;

	return genphy_read_lpa(phydev);
}

static int maxio_resolve_link_compatibility(struct phy_device *phydev)
{
	struct maxio_priv *priv = phydev->priv;
	int interrupt_enable;
	int interrupt_status;
	int phy_status;
	int ret;

	interrupt_enable = phy_read_paged(phydev, MAXIO_AN_INT_PAGE,
					  MAXIO_AN_INT_ENABLE_REG);
	if (interrupt_enable < 0)
		return interrupt_enable;
	if (!(interrupt_enable & MAXIO_AN_COMPLETE_INT_ENABLE))
		return 0;

	phy_status = phy_read_paged(phydev, MAXIO_AN_STATUS_PAGE,
				    MAXIO_PHYSR_REG);
	if (phy_status < 0)
		return phy_status;
	if (!(phy_status & MAXIO_LINK_OK)) {
		priv->link_stable = false;
		return 0;
	}

	interrupt_status = phy_read_paged(phydev, MAXIO_AN_STATUS_PAGE,
					  MAXIO_AN_STATUS_REG);
	if (interrupt_status < 0)
		return interrupt_status;

	if (interrupt_status & MAXIO_AN_COMPLETE) {
		priv->an_retries = 0;
		priv->link_stable = true;
		return 0;
	}

	if (priv->link_stable)
		return 0;

	if (priv->an_retries == MAXIO_AN_MAX_RETRIES) {
		priv->an_retries = 0;
		priv->link_stable = true;
		return 0;
	}

	ret = genphy_restart_aneg(phydev);
	if (ret)
		return ret;

	phydev->link = false;
	priv->an_retries++;

	return 0;
}

static int maxio_mae0621a_read_status(struct phy_device *phydev)
{
	bool old_link = phydev->link;
	int ret;

	ret = genphy_update_link(phydev);
	if (ret)
		return ret;

	if (phydev->autoneg == AUTONEG_ENABLE && old_link && phydev->link)
		return 0;

	phydev->speed = SPEED_UNKNOWN;
	phydev->duplex = DUPLEX_UNKNOWN;
	phydev->pause = false;
	phydev->asym_pause = false;

	ret = maxio_resolve_aneg_linkmode(phydev);
	if (ret)
		return ret;

	if (phydev->autoneg == AUTONEG_ENABLE)
		return maxio_resolve_link_compatibility(phydev);

	return 0;
}

static int maxio_alloc_priv(struct phy_device *phydev)
{
	struct maxio_priv *priv;

	priv = devm_kzalloc(&phydev->mdio.dev, sizeof(*priv), GFP_KERNEL);
	if (!priv)
		return -ENOMEM;

	phydev->priv = priv;

	return 0;
}

static int maxio_mae0621a_q2c_probe(struct phy_device *phydev)
{
	int ret;

	ret = maxio_alloc_priv(phydev);
	if (ret)
		return ret;

	ret = phy_write(phydev, MAXIO_PAGE_SELECT, 0);
	if (ret)
		return ret;

	msleep(100);

	return 0;
}

static int maxio_mae0621a_q3ci_probe(struct phy_device *phydev)
{
	return maxio_alloc_priv(phydev);
}

static int maxio_mae0621a_q2c_config_init(struct phy_device *phydev)
{
	static const struct maxio_reg_write sequence[] = {
		{ 0x0da0, 0x10, 0x0c13 },
		{ 0, 0x0d, 0x0007 },
		{ 0, 0x0e, 0x003c },
		{ 0, 0x0d, 0x4007 },
		{ 0, 0x0e, 0x0000 },
		{ 0x0d96, 0x13, 0x07bc },
		{ 0x0d8f, 0x08, 0x2500 },
		{ 0x0d90, 0x02, 0x1555 },
		{ 0x0d90, 0x05, 0x2b15 },
		{ 0x0d92, 0x14, 0x000a },
		{ 0x0d91, 0x07, 0x5b00 },
		{ 0x0d8f, 0x00, 0x0300 },
		{ 0x0d92, 0x0a, 0x8506 },
		{ 0x0d91, 0x06, 0x6870 },
		{ 0x0d91, 0x01, 0x0940 },
		{ 0x0da0, 0x13, 0x1303 },
		{ 0x0d97, 0x0c, 0x0177 },
		{ 0x0d97, 0x0b, 0x09a9 },
		{ MAXIO_AN_INT_PAGE, MAXIO_AN_INT_ENABLE_REG, 0x0028 },
		{ 0, MII_ADVERTISE, 0x0de1 },
		{ 0, MII_BMCR, 0x9140 },
	};
	int ret;

	ret = maxio_write_sequence(phydev, sequence, ARRAY_SIZE(sequence));
	if (ret)
		return ret;

	ret = maxio_self_check(phydev, 50);
	if (ret)
		return ret;

	msleep(100);

	return 0;
}

static int maxio_mae0621a_q3ci_config_init(struct phy_device *phydev)
{
	static const struct maxio_reg_write sequence[] = {
		{ MAXIO_PHYSR_PAGE, 0x19, 0x0823 },
		{ 0x0dab, 0x17, 0x0c13 },
		{ 0x0d96, 0x15, 0xc08a },
		{ 0x0da4, 0x12, 0x07bc },
		{ 0x0d8f, 0x16, 0x2500 },
		{ 0x0d90, 0x16, 0x1555 },
		{ 0x0d92, 0x11, 0x2b15 },
		{ 0x0d96, 0x16, 0x4010 },
		{ 0x0da5, 0x11, 0x4a12 },
		{ 0x0da5, 0x12, 0x4a12 },
		{ 0x0d99, 0x16, 0x000a },
		{ 0x0d95, 0x13, 0x5b00 },
		{ 0x0d8f, 0x10, 0x0300 },
		{ 0x0d98, 0x17, 0x8506 },
		{ 0x0d95, 0x12, 0x6870 },
		{ 0x0d93, 0x15, 0x0940 },
		{ 0x0dad, 0x12, 0x0303 },
		{ 0x0dad, 0x13, 0x050d },
		{ 0x0dad, 0x14, 0x0d05 },
		{ 0x0dad, 0x15, 0x0505 },
		{ 0x0dad, 0x17, 0x0001 },
		{ 0x0da8, 0x11, 0x0177 },
		{ 0x0da8, 0x10, 0x09a9 },
		{ 0x0da8, 0x12, 0x0868 },
		{ MAXIO_AN_INT_PAGE, MAXIO_AN_INT_ENABLE_REG, 0x0028 },
		{ 0, MII_ADVERTISE, 0x0de1 },
		{ 0, MII_BMCR, 0x9140 },
	};
	int ret;

	ret = maxio_mae0621a_eee_config(phydev);
	if (ret)
		return ret;

	ret = maxio_write_sequence(phydev, sequence, ARRAY_SIZE(sequence));
	if (ret)
		return ret;

	return maxio_mae0621a_led_config(phydev);
}

static int maxio_mae0621a_q2c_resume(struct phy_device *phydev)
{
	int bmcr;
	int ret;

	ret = genphy_resume(phydev);
	if (ret)
		return ret;

	bmcr = phy_read(phydev, MII_BMCR);
	if (bmcr < 0)
		return bmcr;

	ret = phy_write(phydev, MII_BMCR, BMCR_RESET | bmcr);
	if (ret)
		return ret;

	msleep(20);

	return 0;
}

static int maxio_mae0621a_q3ci_resume(struct phy_device *phydev)
{
	static const struct maxio_reg_write sequence[] = {
		{ 0x0daa, 0x17, 0x1001 },
		{ 0x0dab, 0x15, 0x0000 },
	};
	int ret;

	ret = genphy_resume(phydev);
	if (ret)
		return ret;

	return maxio_write_sequence(phydev, sequence, ARRAY_SIZE(sequence));
}

static int maxio_mae0621a_q3ci_suspend(struct phy_device *phydev)
{
	static const struct maxio_reg_write sequence[] = {
		{ 0x0daa, 0x17, 0x1011 },
		{ 0x0dab, 0x15, 0x5550 },
	};
	int ret;

	ret = maxio_write_sequence(phydev, sequence, ARRAY_SIZE(sequence));
	if (ret)
		return ret;

	return genphy_suspend(phydev);
}

static struct phy_driver maxio_drivers[] = {
	{
		PHY_ID_MATCH_EXACT(0x7b744411),
		.name = "MAE0621A-Q2C Gigabit Ethernet",
		.features = PHY_GBIT_FEATURES,
		.probe = maxio_mae0621a_q2c_probe,
		.config_init = maxio_mae0621a_q2c_config_init,
		.config_aneg = genphy_config_aneg,
		.read_status = maxio_mae0621a_read_status,
		.suspend = genphy_suspend,
		.resume = maxio_mae0621a_q2c_resume,
		.read_page = maxio_read_page,
		.write_page = maxio_write_page,
	},
	{
		PHY_ID_MATCH_EXACT(0x7b744412),
		.name = "MAE0621A/B-Q3C(I) Gigabit Ethernet",
		.features = PHY_GBIT_FEATURES,
		.probe = maxio_mae0621a_q3ci_probe,
		.config_init = maxio_mae0621a_q3ci_config_init,
		.config_aneg = genphy_config_aneg,
		.read_status = maxio_mae0621a_read_status,
		.suspend = maxio_mae0621a_q3ci_suspend,
		.resume = maxio_mae0621a_q3ci_resume,
		.read_page = maxio_read_page,
		.write_page = maxio_write_page,
	},
};
module_phy_driver(maxio_drivers);

static const struct mdio_device_id __maybe_unused maxio_tbl[] = {
	{ PHY_ID_MATCH_EXACT(0x7b744411) },
	{ PHY_ID_MATCH_EXACT(0x7b744412) },
	{ }
};
MODULE_DEVICE_TABLE(mdio, maxio_tbl);

MODULE_DESCRIPTION("Maxio Ethernet PHY driver");
MODULE_AUTHOR("Zhao Yang");
MODULE_LICENSE("GPL");
