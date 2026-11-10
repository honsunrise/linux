# SPDX-License-Identifier: GPL-2.0
#
# Realtek RTL8733BS SDIO 802.11ac driver.
#
# Imported from the GPL-2.0 vendor drop carried by the Sipeed LicheeRV Nano
# BSP (osdrv/extdrv/wireless/rtl8733bs tree
# f4282244c91fd7852a7b24c6bda24075e8cbfe47).  Only the RTL8733B/SDIO
# configuration is compiled here; the vendor single-module Makefile is kept
# as rtl8733b.mk for provenance but is not used by Kbuild.

obj-$(CONFIG_RTL8733BS) += rtl8733bs.o

ccflags-y += -DCONFIG_RTL8733B -DCONFIG_SDIO_HCI
ccflags-y += -DCONFIG_LITTLE_ENDIAN
ccflags-y += -DCONFIG_IOCTL_CFG80211 -DRTW_USE_CFG80211_STA_EVENT
ccflags-y += -DCONFIG_AP_MODE -DCONFIG_P2P
ccflags-y += -DCONFIG_MP_INCLUDED
ccflags-y += -DCONFIG_POWER_SAVING
ccflags-y += -DCONFIG_BT_COEXIST
ccflags-y += -DCONFIG_EFUSE_CONFIG_FILE
ccflags-y += -DEFUSE_MAP_PATH=\"/lib/firmware/rtlwifi/wifi_efuse_8733bs.map\"
ccflags-y += -DWIFIMAC_PATH=\"/lib/firmware/rtlwifi/wifimac.txt\"
ccflags-y += -DCONFIG_LOAD_PHY_PARA_FROM_FILE
ccflags-y += -DREALTEK_CONFIG_PATH=\"/lib/firmware/\"
ccflags-y += -DCONFIG_TXPWR_BY_RATE=1 -DCONFIG_TXPWR_BY_RATE_EN=1
ccflags-y += -DCONFIG_TXPWR_LIMIT=1 -DCONFIG_TXPWR_LIMIT_EN=0
ccflags-y += -DCONFIG_RTW_ADAPTIVITY_EN=0 -DCONFIG_RTW_ADAPTIVITY_MODE=0
ccflags-y += -DCONFIG_IEEE80211W
ccflags-y += -DCONFIG_LAYER2_ROAMING -DCONFIG_ROAMING_FLAG=0x3
ccflags-y += -DHIGH_ACTIVE_HST2DEV=0
ccflags-y += -DCONFIG_RTW_SDIO_PM_KEEP_POWER
ccflags-y += -DCONFIG_BR_EXT -DCONFIG_BR_EXT_BRNAME=\"br0\"
ccflags-y += -DCONFIG_RTW_NAPI -DCONFIG_RTW_GRO -DCONFIG_RTW_NETIF_SG
ccflags-y += -DCONFIG_PROC_DEBUG
ccflags-y += -DCONFIG_RTW_UP_MAPPING_RULE=0
ccflags-y += -DDM_ODM_SUPPORT_TYPE=0x04
ccflags-y += -DCONFIG_HALMAC_RS

ccflags-y += -I$(src)/include
ccflags-y += -I$(src)/platform
ccflags-y += -I$(src)/hal/btc
ccflags-y += -I$(src)/hal/phydm
ccflags-y += -I$(src)/core/crypto

rtl8733bs-y := \
	core/rtw_cmd.o \
	core/rtw_security.o \
	core/rtw_debug.o \
	core/rtw_io.o \
	core/rtw_ioctl_query.o \
	core/rtw_ioctl_set.o \
	core/rtw_ieee80211.o \
	core/rtw_mlme.o \
	core/rtw_mlme_ext.o \
	core/rtw_mi.o \
	core/rtw_wlan_util.o \
	core/rtw_vht.o \
	core/rtw_pwrctrl.o \
	core/rtw_rf.o \
	core/rtw_chplan.o \
	core/monitor/rtw_radiotap.o \
	core/rtw_recv.o \
	core/rtw_sta_mgt.o \
	core/rtw_ap.o \
	core/wds/rtw_wds.o \
	core/mesh/rtw_mesh.o \
	core/mesh/rtw_mesh_pathtbl.o \
	core/mesh/rtw_mesh_hwmp.o \
	core/rtw_xmit.o \
	core/rtw_p2p.o \
	core/rtw_rson.o \
	core/rtw_tdls.o \
	core/rtw_br_ext.o \
	core/rtw_iol.o \
	core/rtw_sreset.o \
	core/rtw_btcoex_wifionly.o \
	core/rtw_btcoex.o \
	core/rtw_beamforming.o \
	core/rtw_odm.o \
	core/rtw_rm.o \
	core/rtw_rm_fsm.o \
	core/rtw_ft.o \
	core/rtw_wnm.o \
	core/rtw_mbo.o \
	core/rtw_rm_util.o \
	core/efuse/rtw_efuse.o \
	core/rtw_roch.o \
	core/rtw_sdio.o \
	core/rtw_mp.o \
	core/crypto/aes-internal.o \
	core/crypto/aes-internal-enc.o \
	core/crypto/aes-gcm.o \
	core/crypto/aes-ccm.o \
	core/crypto/aes-omac1.o \
	core/crypto/ccmp.o \
	core/crypto/gcmp.o \
	core/crypto/aes-siv.o \
	core/crypto/aes-ctr.o \
	core/crypto/sha256-internal.o \
	core/crypto/sha256.o \
	core/crypto/sha256-prf.o \
	core/crypto/rtw_crypto_wrap.o \
	core/rtw_swcrypto.o \
	os_dep/osdep_service.o \
	os_dep/linux/os_intfs.o \
	os_dep/linux/sdio_intf.o \
	os_dep/linux/sdio_ops_linux.o \
	os_dep/linux/ioctl_linux.o \
	os_dep/linux/xmit_linux.o \
	os_dep/linux/mlme_linux.o \
	os_dep/linux/recv_linux.o \
	os_dep/linux/ioctl_cfg80211.o \
	os_dep/linux/rtw_cfgvendor.o \
	os_dep/linux/wifi_regd.o \
	os_dep/linux/rtw_android.o \
	os_dep/linux/rtw_proc.o \
	os_dep/linux/nlrtw.o \
	os_dep/linux/rtw_rhashtable.o \
	os_dep/linux/ioctl_mp.o \
	os_dep/linux/custom_gpio_linux.o \
	hal/hal_intf.o \
	hal/hal_com.o \
	hal/hal_com_phycfg.o \
	hal/hal_phy.o \
	hal/hal_dm.o \
	hal/hal_dm_acs.o \
	hal/hal_btcoex_wifionly.o \
	hal/hal_btcoex.o \
	hal/hal_mp.o \
	hal/hal_mcc.o \
	hal/hal_hci/hal_sdio.o \
	hal/led/hal_led.o \
	hal/led/hal_sdio_led.o \
	hal/rtl8733b/rtl8733b_halinit.o \
	hal/rtl8733b/rtl8733b_mac.o \
	hal/rtl8733b/rtl8733b_cmd.o \
	hal/rtl8733b/rtl8733b_phy.o \
	hal/rtl8733b/rtl8733b_ops.o \
	hal/rtl8733b/hal8733b_fw.o \
	hal/rtl8733b/sdio/rtl8733bs_halinit.o \
	hal/rtl8733b/sdio/rtl8733bs_halmac.o \
	hal/rtl8733b/sdio/rtl8733bs_io.o \
	hal/rtl8733b/sdio/rtl8733bs_xmit.o \
	hal/rtl8733b/sdio/rtl8733bs_recv.o \
	hal/rtl8733b/sdio/rtl8733bs_led.o \
	hal/rtl8733b/sdio/rtl8733bs_ops.o \
	hal/efuse/rtl8733b/HalEfuseMask8733B_SDIO.o \
	hal/hal_hci/hal_sdio_coex.o \
	hal/hal_halmac.o \
	hal/halmac-rs/halmac_api.o \
	hal/halmac-rs/halmac_dbg.o \
	hal/halmac-rs/halmac_87xx/halmac_bb_rf_87xx.o \
	hal/halmac-rs/halmac_87xx/halmac_cfg_wmac_87xx.o \
	hal/halmac-rs/halmac_87xx/halmac_common_87xx.o \
	hal/halmac-rs/halmac_87xx/halmac_efuse_87xx.o \
	hal/halmac-rs/halmac_87xx/halmac_flash_87xx.o \
	hal/halmac-rs/halmac_87xx/halmac_fw_87xx.o \
	hal/halmac-rs/halmac_87xx/halmac_gpio_87xx.o \
	hal/halmac-rs/halmac_87xx/halmac_init_87xx.o \
	hal/halmac-rs/halmac_87xx/halmac_mimo_87xx.o \
	hal/halmac-rs/halmac_87xx/halmac_sdio_87xx.o \
	hal/halmac-rs/halmac_87xx/halmac_8733b/halmac_cfg_wmac_8733b.o \
	hal/halmac-rs/halmac_87xx/halmac_8733b/halmac_common_8733b.o \
	hal/halmac-rs/halmac_87xx/halmac_8733b/halmac_gpio_8733b.o \
	hal/halmac-rs/halmac_87xx/halmac_8733b/halmac_init_8733b.o \
	hal/halmac-rs/halmac_87xx/halmac_8733b/halmac_phy_8733b.o \
	hal/halmac-rs/halmac_87xx/halmac_8733b/halmac_pwr_seq_8733b.o \
	hal/halmac-rs/halmac_87xx/halmac_8733b/halmac_sdio_8733b.o \
	hal/phydm/phydm_debug.o \
	hal/phydm/phydm_antdiv.o \
	hal/phydm/phydm_soml.o \
	hal/phydm/phydm_smt_ant.o \
	hal/phydm/phydm_antdect.o \
	hal/phydm/phydm_interface.o \
	hal/phydm/phydm_phystatus.o \
	hal/phydm/phydm_hwconfig.o \
	hal/phydm/phydm.o \
	hal/phydm/phydm_dig.o \
	hal/phydm/phydm_pathdiv.o \
	hal/phydm/phydm_rainfo.o \
	hal/phydm/phydm_dynamictxpower.o \
	hal/phydm/phydm_adaptivity.o \
	hal/phydm/phydm_cfotracking.o \
	hal/phydm/phydm_noisemonitor.o \
	hal/phydm/phydm_beamforming.o \
	hal/phydm/phydm_direct_bf.o \
	hal/phydm/phydm_dfs.o \
	hal/phydm/txbf/halcomtxbf.o \
	hal/phydm/txbf/haltxbfinterface.o \
	hal/phydm/txbf/phydm_hal_txbf_api.o \
	hal/phydm/phydm_adc_sampling.o \
	hal/phydm/phydm_ccx.o \
	hal/phydm/phydm_psd.o \
	hal/phydm/phydm_primary_cca.o \
	hal/phydm/phydm_cck_pd.o \
	hal/phydm/phydm_rssi_monitor.o \
	hal/phydm/phydm_auto_dbg.o \
	hal/phydm/phydm_math_lib.o \
	hal/phydm/phydm_api.o \
	hal/phydm/phydm_pow_train.o \
	hal/phydm/phydm_lna_sat.o \
	hal/phydm/phydm_pmac_tx_setting.o \
	hal/phydm/phydm_mp.o \
	hal/phydm/phydm_cck_rx_pathdiv.o \
	hal/phydm/halrf/halrf.o \
	hal/phydm/halrf/halrf_debug.o \
	hal/phydm/halrf/halphyrf_ce.o \
	hal/phydm/halrf/halrf_powertracking_ce.o \
	hal/phydm/halrf/halrf_powertracking.o \
	hal/phydm/halrf/halrf_kfree.o \
	hal/phydm/halrf/halrf_psd.o \
	hal/phydm/rtl8733b/halhwimg8733b_bb.o \
	hal/phydm/rtl8733b/phydm_hal_api8733b.o \
	hal/phydm/rtl8733b/phydm_regconfig8733b.o \
	hal/phydm/rtl8733b/phydm_rtl8733b.o \
	hal/phydm/halrf/rtl8733b/halrf_8733b.o \
	hal/phydm/halrf/rtl8733b/halrf_iqk_8733b.o \
	hal/phydm/halrf/rtl8733b/halrf_tssi_8733b.o \
	hal/phydm/halrf/rtl8733b/halrf_dpk_8733b.o \
	hal/phydm/halrf/rtl8733b/halrf_txgapk_8733b.o \
	hal/phydm/halrf/rtl8733b/halrf_rfk_init_8733b.o \
	hal/phydm/halrf/rtl8733b/halhwimg8733b_rf.o \
	hal/btc/halbtc8733bwifionly.o \
	hal/btc/halbtccommon.o \
	hal/btc/halbtc8733b.o \
	platform/platform_ops.o
