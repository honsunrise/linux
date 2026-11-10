/* SPDX-License-Identifier: GPL-2.0 */
/*
 * of_gpio.h stub for v7.1 kernel
 *
 * Upstream v6.14 removed the public <linux/of_gpio.h> API and made
 * gpiolib-of internal. ~141 out-of-tree vendor BSP files still
 * include <linux/of_gpio.h> and ~46 of them call of_get_gpio()
 * variants at runtime.
 *
 * There's no upstream migration path that fits nicely as a header
 * shim: the replacement API (gpiod_get_from_of_node) takes very
 * different args and returns a struct gpio_desc* rather than a
 * numeric gpio, so a mechanical wrapper isn't correct.
 *
 * For now, provide inline stubs that return -ENOSYS. Vendor drivers
 * doing GPIO discovery via DT will fail at runtime; probe of those
 * drivers will error out but the kernel itself boots. Migrate
 * individual drivers to gpiod API as needed once we have a booting
 * baseline.
 */
#ifndef __LINUX_OF_GPIO_COMPAT_H
#define __LINUX_OF_GPIO_COMPAT_H

#include <linux/errno.h>
#include <linux/of.h>

struct device_node;

enum of_gpio_flags {
	OF_GPIO_ACTIVE_LOW      = 0x1,
	OF_GPIO_SINGLE_ENDED    = 0x2,
	OF_GPIO_OPEN_DRAIN      = 0x4,
	OF_GPIO_TRANSITORY      = 0x8,
	OF_GPIO_PULL_UP         = 0x10,
	OF_GPIO_PULL_DOWN       = 0x20,
	OF_GPIO_PULL_DISABLE    = 0x40,
};

static inline int of_get_named_gpio(const struct device_node *np,
				    const char *propname, int index)
{
	return -ENOSYS;
}

static inline int of_get_gpio(const struct device_node *np, int index)
{
	return -ENOSYS;
}

static inline int of_gpio_named_count(const struct device_node *np,
				      const char *propname)
{
	return -ENOSYS;
}

static inline int of_gpio_count(const struct device_node *np)
{
	return -ENOSYS;
}

#endif /* __LINUX_OF_GPIO_COMPAT_H */
