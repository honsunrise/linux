# SPDX-License-Identifier: GPL-2.0

ifeq ($(CONFIG_AW_BSP),y)
# Full Allwinner BSP. These subtrees are sunxi-specific and must not be
# traversed on Rockchip or RISC-V builds.
obj-y += drivers/
obj-y += modules/nand/
obj-y += modules/gpu/
else
# Outside the Allwinner BSP the AIC8800 driver is still supported: it is a
# generic SDIO/USB driver used by Rockchip and RISC-V boards too.
obj-$(CONFIG_AIC_WLAN_SUPPORT) += drivers/net/wireless/aic8800/
endif
