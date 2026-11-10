# SPDX-License-Identifier: GPL-2.0
#
# Sophgo osdrv multimedia drivers for the SG2002 (cv181x), in-tree build.
#
# Sources: sophgo/osdrv @ f35ca075cc022aac97f5d22238c1e46caf8276bd, interdrv/
# (GPL-2.0), with the Linux 7.2 port of the sys/base/snsr_i2c/cif/vi/vpss/
# vcodec/jpeg/cvi_vc_drv/tpu modules from
# djairjr/recamera-linux-kernel7 @ 240adcc6164d7ff50995c0119f29a1ba570ea57d
# (external/package/sophgo-osdrv/000{1,2,3}-*.patch, each change marked
# "7.2 port"). The remaining modules (vo, mipi_tx, fb, ive, dwa, rgn, mon,
# rtos_cmdqu, fast_image, wiegand, clock_cooling) use the same port.
#
# The include order per module matters: the module's own directory must come
# before base/ and sys/, which also have reg.h and a few other headers with
# the same basename.

CVIARCH_L := cv181x

# Vendor build switches (Makefile.interdrv.param and the vendor Kconfigs).
ccflags-y += -D__CV181X__
# The ION Kconfig symbols: they change the layout of struct ion_buffer
# (name, paddr, ...) which is shared with cvi_ion.
ccflags-y += -DCONFIG_ION=1 -DCONFIG_ION_CARVEOUT_HEAP=1 -DCONFIG_ION_CVITEK=1

# Paths shared by every module.
ccflags-y += -I$(src)/include/common/uapi \
	     -I$(src)/include/common/kapi \
	     -I$(src)/include/chip/$(CVIARCH_L)/uapi \
	     -I$(src)/include/chip/$(CVIARCH_L)/uapi/linux \
	     -I$(src)/include \
	     -I$(src)/../ion -I$(src)/../ion/uapi

# Vendor style: dozens of cross-file functions are not declared in headers.
WNO_VENDOR := -Wno-missing-prototypes -Wno-missing-declarations

# --- sys: /dev/cvi-sys, the shared memory map between the modules ----------
obj-$(CONFIG_SOPHGO_OSDRV_SYS) += $(CVIARCH_L)_sys.o
$(CVIARCH_L)_sys-y := sys/common/sys.o sys/common/sys_context.o
$(foreach o,$($(CVIARCH_L)_sys-y),$(eval CFLAGS_$(o) += \
	-I$(src)/sys/common -I$(src)/sys/common/uapi -I$(src)/sys/common/kapi \
	-I$(src)/sys/hal/$(CVIARCH_L) -I$(src)/sys/hal/$(CVIARCH_L)/uapi \
	-I$(src)/base/mw -I$(src)/base))

# --- base: vip_sys register access, the vb (video buffer) pool, procfs -----
obj-$(CONFIG_SOPHGO_OSDRV_BASE) += $(CVIARCH_L)_base.o
$(CVIARCH_L)_base-y := base/base.o base/chip/$(CVIARCH_L)/vip_sys.o base/reg.o \
	base/cvi_vb_proc.o base/cvi_log_proc.o base/cvi_sys_proc.o \
	base/base_context.o base/vb.o
$(foreach o,$($(CVIARCH_L)_base-y),$(eval CFLAGS_$(o) += \
	-I$(src)/base -I$(src)/base/chip/$(CVIARCH_L) \
	-I$(src)/base/mw -I$(src)/sys/common -I$(src)/sys/common/uapi $(WNO_VENDOR)))

# --- snsr_i2c: sensor I2C writes synchronised with the frame start ---------
obj-$(CONFIG_SOPHGO_OSDRV_SNSR_I2C) += snsr_i2c.o
snsr_i2c-y := snsr_i2c/common/snsr_i2c.o
$(foreach o,$(snsr_i2c-y),$(eval CFLAGS_$(o) += \
	-I$(src)/snsr_i2c/common -I$(src)/snsr_i2c/chip/$(CVIARCH_L)))

# --- cif: cvi_mipi_rx, the MIPI-CSI receivers and sensor MCLK --------------
# kernel-5.10-headers: the vendor pinctrl headers (drivers/pinctrl/cvitek)
# which cif and vo include.
obj-$(CONFIG_SOPHGO_OSDRV_MIPI_RX) += cvi_mipi_rx.o
cvi_mipi_rx-y := cif/chip/$(CVIARCH_L)/cif.o cif/chip/$(CVIARCH_L)/drv/cif_drv.o
# CONFIG_COMMON_CLK_CVITEK: take the CCF MCLK path (clk_set_rate + enable)
# instead of the vendor's raw CAM0 divider write.
$(foreach o,$(cvi_mipi_rx-y),$(eval CFLAGS_$(o) += \
	-I$(src)/cif/chip/$(CVIARCH_L) -I$(src)/cif/common \
	-I$(src)/kernel-5.10-headers -I$(src)/snsr_i2c/common \
	-I$(src)/base/chip/$(CVIARCH_L) -DCONFIG_COMMON_CLK_CVITEK $(WNO_VENDOR)))

# --- vi: cv181x_vi, the video input + ISP ----------------------------------
vi-dir := vi/chip/$(CVIARCH_L)
obj-$(CONFIG_SOPHGO_OSDRV_VI) += cv181x_vi.o
cv181x_vi-y := vi/common/vi_core.o \
	$(vi-dir)/vi.o $(vi-dir)/vi_ext.o $(vi-dir)/cmdq.o $(vi-dir)/vi_sdk_layer.o \
	$(vi-dir)/vi_isp_buf_ctrl.o $(vi-dir)/vi_raw_dump.o \
	$(vi-dir)/vip/vi_drv.o $(vi-dir)/vip/vi_subsys_ctrl.o $(vi-dir)/vip/vi_fe_ip_ctrl.o \
	$(vi-dir)/vip/vi_be_ip_ctrl.o $(vi-dir)/vip/vi_raw_ip_ctrl.o $(vi-dir)/vip/vi_rgb_ip_ctrl.o \
	$(vi-dir)/vip/vi_yuv_ip_ctrl.o $(vi-dir)/vip/vi_tun_ip_ctrl.o $(vi-dir)/vip/vi_ip_test_case.o \
	$(vi-dir)/vip/vi_perf_chk.o \
	$(vi-dir)/proc/vi_proc.o $(vi-dir)/proc/vi_dbg_proc.o $(vi-dir)/proc/vi_isp_proc.o
$(foreach o,$(cv181x_vi-y),$(eval CFLAGS_$(o) += \
	-I$(src)/$(vi-dir) -I$(src)/vi/common -I$(src)/include \
	-I$(src)/base -I$(src)/base/chip/$(CVIARCH_L) \
	-I$(src)/sys/common -I$(src)/sys/common/uapi $(WNO_VENDOR)))

# --- vpss: cv181x_vpss, scaling / colour conversion / OSD blending ---------
vpss-dir := vpss/chip/$(CVIARCH_L)
obj-$(CONFIG_SOPHGO_OSDRV_VPSS) += cv181x_vpss.o
cv181x_vpss-y := vpss/common/cvi_vip_vpss_proc.o vpss/common/reg.o vpss/common/vpss.o \
	vpss/common/vpss_rgn_ctrl.o vpss/common/vpss_ioctl.o \
	$(vpss-dir)/vip_img.o $(vpss-dir)/vip_sc.o $(vpss-dir)/dsi_phy.o \
	$(vpss-dir)/scaler.o $(vpss-dir)/vpss_core.o
$(foreach o,$(cv181x_vpss-y),$(eval CFLAGS_$(o) += \
	-I$(src)/$(vpss-dir) -I$(src)/vpss/common -I$(src)/include \
	-I$(src)/base -I$(src)/base/chip/$(CVIARCH_L) \
	-I$(src)/sys/common -I$(src)/sys/common/uapi \
	-DCONFIG_CVI_LOG -DCONFIG_REG_DUMP -DCONFIG_TILE_MODE $(WNO_VENDOR)))

# --- dwa: cv181x_dwa, the dewarp engine (GDC / LDC / mesh) -----------------
dwa-dir := dwa/chip/$(CVIARCH_L)
obj-$(CONFIG_SOPHGO_OSDRV_DWA) += $(CVIARCH_L)_dwa.o
$(CVIARCH_L)_dwa-y := common/dwa_platform.o common/cvi_vip_gdc_proc.o \
	$(dwa-dir)/cmdq.o $(dwa-dir)/vip_dwa.o $(dwa-dir)/gdc.o $(dwa-dir)/ldc.o \
	$(dwa-dir)/mesh.o $(dwa-dir)/ldc_test.o
$(foreach o,$($(CVIARCH_L)_dwa-y),$(eval CFLAGS_$(o) += \
	-I$(src)/$(dwa-dir) -I$(src)/dwa/common \
	-I$(src)/base -I$(src)/base/chip/$(CVIARCH_L) \
	-I$(src)/sys/common -I$(src)/sys/common/uapi $(WNO_VENDOR)))

# --- rgn: cv181x_rgn, the OSD region (overlay) engine ----------------------
rgn-dir := rgn/chip/$(CVIARCH_L)
obj-$(CONFIG_SOPHGO_OSDRV_RGN) += $(CVIARCH_L)_rgn.o
$(CVIARCH_L)_rgn-y := common/rgn_core.o $(rgn-dir)/rgn.o \
	$(rgn-dir)/vip/rgn_drv.o $(rgn-dir)/proc/rgn_proc.o
$(foreach o,$($(CVIARCH_L)_rgn-y),$(eval CFLAGS_$(o) += \
	-I$(src)/$(rgn-dir) -I$(src)/rgn/common -I$(src)/rtos_cmdqu \
	-I$(src)/base -I$(src)/base/chip/$(CVIARCH_L) \
	-I$(src)/sys/common -I$(src)/sys/common/uapi $(WNO_VENDOR)))

# --- vo: cv181x_vo, the display controller (DSI / BT / LVDS) --------------
vo-dir := vo/chip/$(CVIARCH_L)
obj-$(CONFIG_SOPHGO_OSDRV_VO) += $(CVIARCH_L)_vo.o
$(CVIARCH_L)_vo-y := common/vo_core.o common/vo_rgn_ctrl.o \
	$(vo-dir)/vo.o $(vo-dir)/vo_sdk_layer.o \
	$(vo-dir)/proc/vo_disp_proc.o $(vo-dir)/proc/vo_proc.o
$(foreach o,$($(CVIARCH_L)_vo-y),$(eval CFLAGS_$(o) += \
	-I$(src)/$(vo-dir) -I$(src)/vo/common \
	-I$(src)/vpss/chip/$(CVIARCH_L) -I$(src)/vpss/common \
	-I$(src)/base -I$(src)/base/chip/$(CVIARCH_L) \
	-I$(src)/sys/common -I$(src)/sys/common/uapi \
	-I$(src)/kernel-5.10-headers -DCONFIG_CVI_LOG $(WNO_VENDOR)))

# --- mipi_tx: cv181x_mipi_tx, the DSI host + D-PHY (part of the vo dir) ----
obj-$(CONFIG_SOPHGO_OSDRV_MIPI_TX) += $(CVIARCH_L)_mipi_tx.o
$(CVIARCH_L)_mipi_tx-y := $(vo-dir)/vo_mipi_tx.o $(vo-dir)/proc/vo_mipi_tx_proc.o
$(foreach o,$($(CVIARCH_L)_mipi_tx-y),$(eval CFLAGS_$(o) += \
	-I$(src)/$(vo-dir) -I$(src)/vo/common \
	-I$(src)/vpss/chip/$(CVIARCH_L) -I$(src)/vpss/common \
	-I$(src)/base -I$(src)/base/chip/$(CVIARCH_L) \
	-I$(src)/sys/common -I$(src)/sys/common/uapi \
	-I$(src)/kernel-5.10-headers -DCONFIG_CVI_LOG $(WNO_VENDOR)))

# --- fb: cvi_fb, the framebuffer on top of vo + vpss -----------------------
obj-$(CONFIG_SOPHGO_OSDRV_FB) += cvi_fb.o
cvi_fb-y := fb/cvifb.o
$(foreach o,$(cvi_fb-y),$(eval CFLAGS_$(o) += \
	-I$(src)/fb -I$(src)/base -I$(src)/base/chip/$(CVIARCH_L) \
	-I$(src)/vpss/chip/$(CVIARCH_L) -I$(src)/vpss/common \
	-I$(src)/sys/common -I$(src)/sys/common/uapi $(WNO_VENDOR)))

# --- ive: cv181x_ive, the image/video acceleration engine ------------------
ive-dir := ive/hal/$(CVIARCH_L)
obj-$(CONFIG_SOPHGO_OSDRV_IVE) += $(CVIARCH_L)_ive.o
$(CVIARCH_L)_ive-y := ive/common/cvi_ive_interface.o \
	$(ive-dir)/cvi_reg.o $(ive-dir)/cvi_ive_platform.o
$(foreach o,$($(CVIARCH_L)_ive-y),$(eval CFLAGS_$(o) += \
	-I$(src)/ive/common -I$(src)/$(ive-dir) -I$(src)/$(ive-dir)/include \
	-I$(src)/base -I$(src)/base/chip/$(CVIARCH_L) \
	-I$(src)/sys/common -I$(src)/sys/common/uapi $(WNO_VENDOR)))

# --- mon: cv181x_mon, the DDR/PC monitor ----------------------------------
mon-dir := mon/hal/$(CVIARCH_L)
obj-$(CONFIG_SOPHGO_OSDRV_MON) += $(CVIARCH_L)_mon.o
$(CVIARCH_L)_mon-y := mon/common/cvi_mon_interface.o $(mon-dir)/mon_platform.o
$(foreach o,$($(CVIARCH_L)_mon-y),$(eval CFLAGS_$(o) += \
	-I$(src)/mon/common -I$(src)/$(mon-dir) $(WNO_VENDOR)))

# --- clock_cooling: cv181x_clock_cooling, the thermal cooling device -------
cc-dir := clock_cooling/$(CVIARCH_L)
obj-$(CONFIG_SOPHGO_OSDRV_CLOCK_COOLING) += $(CVIARCH_L)_clock_cooling.o
$(CVIARCH_L)_clock_cooling-y := $(cc-dir)/clock_cooling.o
$(foreach o,$($(CVIARCH_L)_clock_cooling-y),$(eval CFLAGS_$(o) += \
	-I$(src)/clock_cooling -I$(src)/$(cc-dir)))

# --- rtos_cmdqu: the mailbox to the C906L FreeRTOS core --------------------
obj-$(CONFIG_SOPHGO_OSDRV_RTOS_CMDQU) += $(CVIARCH_L)_rtos_cmdqu.o
$(CVIARCH_L)_rtos_cmdqu-y := rtos_cmdqu/rtos_cmdqu.o rtos_cmdqu/rtos_cmdqu_cb.o \
	rtos_cmdqu/cvi_spinlock.o
$(foreach o,$($(CVIARCH_L)_rtos_cmdqu-y),$(eval CFLAGS_$(o) += \
	-I$(src)/rtos_cmdqu -I$(src)/base $(WNO_VENDOR)))

# --- fast_image: the FastRTOS image loader (uses rtos_cmdqu) ---------------
obj-$(CONFIG_SOPHGO_OSDRV_FAST_IMAGE) += $(CVIARCH_L)_fast_image.o
$(CVIARCH_L)_fast_image-y := fast_image/fast_image.o
$(foreach o,$($(CVIARCH_L)_fast_image-y),$(eval CFLAGS_$(o) += \
	-I$(src)/fast_image -I$(src)/rtos_cmdqu -I$(src)/include \
	-I$(src)/base -I$(src)/base/chip/$(CVIARCH_L) \
	-I$(src)/sys/common -I$(src)/sys/common/uapi $(WNO_VENDOR)))

# --- wiegand: cvi_wiegand, the Wiegand interface controllers --------------
obj-$(CONFIG_SOPHGO_OSDRV_WIEGAND) += cvi_wiegand.o
cvi_wiegand-y := wiegand/cvi_wiegand.o
$(foreach o,$(cvi_wiegand-y),$(eval CFLAGS_$(o) += -I$(src)/wiegand))

# --- tpu: cv181x_tpu, the NPU (TDMA + TIU command processor) --------------
obj-$(CONFIG_SOPHGO_OSDRV_TPU) += $(CVIARCH_L)_tpu.o
$(CVIARCH_L)_tpu-y := tpu/common/cvi_tpu_interface.o \
	tpu/hal/$(CVIARCH_L)/tpu_platform.o tpu/hal/$(CVIARCH_L)/tpu_pmu.o
$(foreach o,$($(CVIARCH_L)_tpu-y),$(eval CFLAGS_$(o) += \
	-I$(src)/tpu/common -I$(src)/tpu/hal/$(CVIARCH_L) \
	-I$(src)/include/uapi -I$(src)/include/chip/$(CVIARCH_L)/uapi/linux \
	-I$(src)/../ion/ion $(WNO_VENDOR)))

# --- vcodec: cv181x_vcodec, the H.264/H.265 register + IRQ front end ------
obj-$(CONFIG_SOPHGO_OSDRV_VCODEC) += $(CVIARCH_L)_vcodec.o
$(CVIARCH_L)_vcodec-y := vcodec/cvi_vcodec.o vcodec/vcodec_common.o \
	vcodec/hal/$(CVIARCH_L)/cvi_vcodec_cfg.o
$(foreach o,$($(CVIARCH_L)_vcodec-y),$(eval CFLAGS_$(o) += \
	-I$(src)/vcodec -DCNM_FPGA_PLATFORM -DCNM_FPGA_PCI_INTERFACE \
	-DCVI_H26X_USE_ION_FW_BUFFER -DUSE_KERNEL_MODE $(WNO_VENDOR)))

# --- jpeg: cv181x_jpeg, the JPEG encoder/decoder front end ----------------
obj-$(CONFIG_SOPHGO_OSDRV_JPEG) += $(CVIARCH_L)_jpeg.o
$(CVIARCH_L)_jpeg-y := jpeg/cvi_jpeg.o jpeg/jpeg_common.o jpeg/jmm.o \
	jpeg/hal/$(CVIARCH_L)/cvi_jpeg_cfg.o
$(foreach o,$($(CVIARCH_L)_jpeg-y),$(eval CFLAGS_$(o) += \
	-I$(src)/jpeg -DCHIP_BM1880 -DASIC_EVB -DUSE_KERNEL_MODE $(WNO_VENDOR)))

# --- cvi_vc_driver: the Chips&Media VPU/JPU API and the venc/vdec nodes ----
vc-dir := cvi_vc_drv
vc-enc := $(vc-dir)/vcodec
vc-jpg := $(vc-dir)/jpeg
obj-$(CONFIG_SOPHGO_OSDRV_VC_DRIVER) += cvi_vc_driver.o
cvi_vc_driver-y := $(vc-dir)/common/rcKernel/cvi_rc_kernel.o \
	$(vc-dir)/common/rcKernel/cvi_float_point/cvi_float_point.o \
	$(vc-dir)/common/rcKernel/cvi_float_point/cvi_soft_float.o \
	$(vc-enc)/sample/main_enc_cvitest.o \
	$(vc-enc)/sample/helper/main_helper.o $(vc-enc)/sample/helper/vpuhelper.o \
	$(vc-enc)/sample/helper/bitstream/bitstreamfeeder.o $(vc-enc)/sample/helper/bitstream/bitstreamreader.o \
	$(vc-enc)/sample/helper/bitstream/bsfeeder_fixedsize_impl.o $(vc-enc)/sample/helper/bitstream/bsfeeder_es_in_impl.o \
	$(vc-enc)/sample/helper/comparator/comparator.o $(vc-enc)/sample/helper/display/simplerenderer.o \
	$(vc-enc)/sample/helper/misc/cfgParser.o $(vc-enc)/sample/helper/misc/cnm_video_helper.o \
	$(vc-enc)/sample/helper/misc/datastructure.o $(vc-enc)/sample/helper/misc/platform.o \
	$(vc-enc)/sample/helper/misc/debug.o $(vc-enc)/sample/helper/misc/pbu.o \
	$(vc-enc)/sample/helper/yuv/yuvfeeder.o $(vc-enc)/sample/helper/yuv/yuvAddrfeeder.o \
	$(vc-enc)/vdi/linux/vdi.o $(vc-enc)/vdi/linux/vdi_osal.o \
	$(vc-enc)/vpuapi/product.o $(vc-enc)/vpuapi/vpuapifunc.o $(vc-enc)/vpuapi/vpuapi.o \
	$(vc-enc)/vpuapi/coda9/coda9.o $(vc-enc)/vpuapi/wave/common/common.o $(vc-enc)/vpuapi/wave/wave4/wave4.o \
	$(vc-enc)/cvi/cvi_enc_rc.o $(vc-enc)/cvi/cvi_vcodec_lib.o $(vc-enc)/cvi/cvi_enc_internal.o \
	$(vc-enc)/cvi/cvi_dec_internal.o $(vc-enc)/cvi/cvi_vdec_api.o \
	$(vc-enc)/cvi/cvi_h265_dec.o $(vc-enc)/cvi/cvi_h264_dec.o \
	$(vc-jpg)/jdi/linux/jdi.o $(vc-jpg)/jpuapi/jpuapi.o $(vc-jpg)/jpuapi/jpuapifunc.o \
	$(vc-jpg)/src/jpuhelper.o $(vc-jpg)/src/jpulog.o $(vc-jpg)/src/mixer.o \
	$(vc-jpg)/cvi_jpg_interface/src/cvi_jpg_interface.o \
	$(vc-jpg)/cvi_jpg_interface/src/cvi_jpg_dec_internal.o \
	$(vc-jpg)/cvi_jpg_interface/src/cvi_jpg_enc_internal.o \
	$(vc-jpg)/cvi_jpg_interface/test/cvi_jpg_codec.o \
	$(vc-dir)/module/src/enc_ctx.o $(vc-dir)/module/src/cvi_venc.o $(vc-dir)/module/src/cvi_vdec.o \
	$(vc-dir)/cvi_vc_drv.o $(vc-dir)/cvi_vc_drv_proc.o
vc-inc := $(vc-dir) $(vc-dir)/include $(vc-dir)/common \
	$(vc-enc) $(vc-enc)/sample $(vc-enc)/sample/helper $(vc-enc)/sample/helper/misc \
	$(vc-enc)/vpuapi $(vc-enc)/vdi $(vc-enc)/cvi \
	$(vc-jpg) $(vc-jpg)/include $(vc-jpg)/jdi $(vc-jpg)/jdi/linux $(vc-jpg)/jpuapi $(vc-jpg)/src \
	$(vc-jpg)/cvi_jpg_interface $(vc-jpg)/cvi_jpg_interface/src $(vc-jpg)/cvi_jpg_interface/inc \
	$(vc-dir)/module/include include
$(foreach o,$(cvi_vc_driver-y),$(eval CFLAGS_$(o) += $(addprefix -I$(src)/,$(vc-inc)) \
	-I$(src)/base -I$(src)/base/chip/$(CVIARCH_L) \
	-I$(src)/sys/common -I$(src)/sys/common/uapi \
	-DUSE_KERNEL_MODE -DCVI_H26X_USE_ION_MEM -DCVI_JPG_USE_ION_MEM \
	-DBITSTREAM_ION_CACHED_MEM -DMJPEG_INTERFACE_API \
	-DCVI_H26X_ES_BUFFER_QUEUE_ENABLE -DCVI_H26X_USE_ION_FW_BUFFER \
	-DENV_SET_ADDR_REMAP -DENABLE_DEC -DVC_DEBUG_BASIC_LEVEL $(WNO_VENDOR)))
