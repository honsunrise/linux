# SPDX-License-Identifier: GPL-2.0
#
# Realtek RTL8733BS SDIO Bluetooth HCI transport.
#
# Imported from the same GPL-2.0 Sipeed LicheeRV Nano BSP tree as the
# rtl8733bs WiFi driver:
# osdrv/extdrv/wireless/rtl8733bs_bt_sdio tree
# 9282d4471c696b2d224b47685152f5ab6cd4365c.
# The WiFi driver exports rtw_sdio_multi_state for the combo interface.

obj-$(CONFIG_RTK_BTSDIO) += btrtksdio.o

btrtksdio-y := btrtl.o btrtk_sdio.o rtk_coex.o

ccflags-y += -DCONFIG_COMBO_MULTISDIO_EXPORT_FROM_RTW
