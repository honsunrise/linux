This repository is an UNOFFICIAL fork of the Linux kernel.

  Upstream base : Linux stable v7.3.4 (7595a62d45ee1a2297eafa5f2ef5d0a45142d84d)
  Vendor source : https://github.com/radxa/kernel, linux-7.0.11 at c3e71bed930b
                  (selected board fixes, not a wholesale vendor merge)
  Maintenance   : sbc-7.3.4; shared board support, one active release branch

  Pipeline      : Radxa  (309 vendor commits on stable v7.0.11)
                  → drop noise   (-3 historical wip, -1 pmic-glink HACK, -2 PKGBUILD)
                  → rebase --signoff onto stable v7.1.2, --empty=drop
                  → keep the existing v7.1 forward-port and refresh the stable base
                  → sync Radxa 7.0.11-2 delta: 7 ported, 1 already upstream, 1 HACK omitted
                  → 263 carried vendor commits at v7.1 HEAD 2ca9a714e4e3
                  → merge stable v7.2.10 without rewriting vendor history
                  → combine Qualcomm and A733 BSP, including d7fedd983a2b
                  → port the net fork delta from official v7.2.10 to v7.3.3
                    while retaining both parent histories
                  → freeze that history as sbc-7.3.3 at 9cf00fc47d8a
                  → reconstruct 16 functional downstream commits on v7.3.3
                  → cherry-pick that series onto official v7.3.4

  Attribution   : Original author and DCO history is retained on sbc-7.3.3.
                  Consolidated commits identify their source commit/base;
                  existing copyright notices and SPDX identifiers are unchanged.
                  AI-assisted changes do not add a human Signed-off-by.

  Branch policy
    Each release has an sbc-<kernel-version> branch based directly on the
    corresponding official stable tag. Only the latest release is actively
    maintained; previous version branches are frozen for reproducibility and
    rollback. sbc-7.3.3 preserves commit 9cf00fc47d8a without rewriting it.
    There is no rolling sbc alias and no separate branch for each board.

    To upgrade, verify the official tag, create the new version branch at
    that tag, then cherry-pick the previous release's downstream-only commits
    in order. After this initial normalization, that range is
    v<old-version>..sbc-<old-version>. Use cherry-pick -x for provenance.
    Include carried vendor/community prerequisites, not just commits by the
    fork maintainer. Drop a patch only after confirming upstream supplies its
    behaviour; resolve conflicts against the new APIs, never by copying old
    files wholesale over upstream. Do not merge the previous release branch.

    Update release/module versions and these notes, compare the patch series,
    and validate the board profiles before publishing and moving the GitHub
    default branch. Upstream/stable/vendor remotes remain source references.
    Consumer Nix revisions/hashes and deployed systems are separate changes.

  Initial patch-stack normalization and v7.3.4 replay
    The old mixed ancestry is not a cherry-pick range: it includes thousands
    of historical stable/vendor commits. Its net delta was partitioned into
    BSP/AIC, shared core/build APIs, Sophgo, controllers, Ethernet, PCI and
    firmware, display, media, connectivity, Realtek, input, Qualcomm boards,
    Rockchip boards, Allwinner boards, retained Amlogic boards and documentation.
    Reconstructing these 16 commits on v7.3.3 reproduced the frozen source tree
    exactly: 16eed3f02a24f5849fae59ac7d85bbf6a0579c93 (including file modes
    and deletions). This preserves the Q6A host-pad and headless-DTB follow-ups.

    The initial replay matched an independent three-way integration tree after
    resolving the sole conflicting file, pcie-qcom.c. Retain the downstream
    bridge predicate (PCI node type plus bus-range or bridge class), which
    already includes upstream's PCI-node-type guard, and use upstream's
    updated comment. Iris IOVA reservation/power sequencing, PCI link-speed
    initialization and GENI firmware validation fixes from v7.3.4 are retained.
    Final range-diff additionally records removal of the superseded Iris DT
    workaround below; other differences are PCIe reconciliation and Makefile
    version context.

    Upstream 190082e89a42 reserves [0, 0x25800000) in the Iris driver. The old
    Q8B, Q6A and CM-Q64 iris-iova DT nodes reserve that same range in the IOMMU
    domain before probe, making dma_iova_try_alloc fail under the driver's
    temporary bus DMA limit. These DT nodes and their memory-region references
    are therefore removed from the replayed Qualcomm board patch. Physical
    firmware carveouts and firmware names are retained. IOVA ownership now
    belongs to the driver; the DT workaround mentioned in historical notes
    below applies only to the older release.

  Board configuration (all commands also take ARCH and CROSS_COMPILE)

    Board                    Base configuration       Final fragment
    Q6A / CM-Q64             qcom_module_defconfig    radxa_q6a_headless.config
    Dragon Q8B               qcom_module_defconfig    radxa_q8b.config
    ZERO 3W                  defconfig                radxa_zero3w.config
    NanoPC-T4                defconfig                nanopc_t4.config
    Cubie A7A/A7S/A7Z         KBUILD_DEFCONFIG=bsp.config, then
                             defconfig radxa.config radxa_custom.config
    LicheeRV Nano (riscv)     defconfig                licheerv_nano.config

    For example, from the repository root:
      make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=../build-q8b \
           qcom_module_defconfig radxa_q8b.config
      make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=../build-q8b \
           -j4 Image modules dtbs

    Keep separate O= directories for distinct configurations. Do not apply
    radxa_custom.config to Qualcomm or Rockchip: it intentionally disables
    features that their boards need. BSP_TOP=bsp/ and LICHEE_KERN_DIR=./
    now have defaults, including for non-Allwinner builds.

    For a Q6A KVM host without audio, select
    qcom/qcs6490-radxa-dragon-q6a-kvm-headless.dtb together with the
    radxa_q6a_headless.config fragment. This optional DTB disables only
    sound, wcd938x and q6apm nodes; the kernel fragment controls KMS.
    Ordinary Q6A and KVM DTBs retain their existing audio/display policy.

    ZERO 3W has distinct rk3566-radxa-zero-3w-aic8800ds2.dtb and
    rk3566-radxa-zero-3w-ap6212.dtb variants. Select the one matching the
    physical module; the original rk3566-radxa-zero-3w.dtb is retained.

    LicheeRV Nano uses ARCH=riscv and a riscv64-linux-gnu- toolchain. Choose
    sg2002-licheerv-nano-{b,e,w,we}.dtb to match the board: B has neither
    Ethernet nor wireless, E has Ethernet, W has wireless, WE has both.
    The profile enables STAGING and the rebuilt Sophgo multimedia modules;
    do not reuse the binary .ko files from the old 5.10 firmware image.

    Optional touch controllers share reset/IRQ lines and are disabled in
    the base DTBs. Select exactly one matching the fip's panel= setting:
      gt911   : zct2133v1 / mtd700920b
      cst7xx  : st7701_lct024bsi20
      cst3240 : st7701_hd228001c31
    Precomposed WE DTBs are sg2002-licheerv-nano-we-{gt911,cst7xx,cst3240}.dtb.
    For another board variant, apply the corresponding
    sg2002-licheerv-nano-touch-*.dtbo to its base DTB with fdtoverlay before
    packaging the boot image. These overlays select touch, not the display
    firmware's panel initialization.

  Current integration boundaries
    - Q8B: retain TC956x Ethernet and its RX FIFO headroom fix; restore the
      normal AXI rate, M.2 PCIe/USB/UART power sequencing, thermal fallback
      trips, QUP firmware, WCD9385, SD power cycling and ADP12V monitoring.
      The required STMMAC DMA-device separation is ported from Alex Elder's
      Radxa commit bd35baf53330: TC956x DMA uses its PCI function while
      device lifetime and runtime PM stay on the auxiliary MAC device.
      Other STMMAC platforms default to their original DMA device.
      Supply the DTB from this tree explicitly to the bootloader; do not
      silently use a different DTB embedded in the board's UEFI firmware.
    - Linux 7.3 uses pwrseq_enable/disable and atomic DRM bridge callbacks.
      PAS attachment retains externally owned firmware/resources; handover
      IRQ state is owned by the updated q6v5 core. DP CEC follows the EDID
      lifetime in dp_display rather than the removed dp_panel EDID cache.
    - A733 retains its BSP providers, UFS/MMC and dwmac-sun55i GMAC210 path,
      including the A7A RGMII TX timing fix. The level-high UFS IRQ and
      deployment-specific irqpoll remain bring-up settings, not newly
      established hardware requirements. Do not substitute the discarded
      experimental mainline provider stack for this BSP configuration.
    - AIC8800 is one shared source tree under bsp/drivers/net/wireless.
      It can be built without AW_BSP, using normal SDIO power sequencing;
      it carries cfg80211 API adaptations through Linux 7.3.
    - Sophgo multimedia sources and their ION/MPI ABI are documented in
      drivers/staging/sophgo/README. Old 5.10 binary kernel modules cannot
      be loaded into this kernel. A successful compile is not proof of
      sensor, display, codec, TPU or IVE operation on a physical board.

  Q6A UFS host-pad supply
    Schematic V1.21, printed sheet 11 (PDF page 9), connects QCS6490
    VDD_PX10 / L23 (UFS pads) to PM7325 VREG_L9B_1P2. Sheet 21 also
    identifies L9B as "PX10, UFS0_VCCQ". The board DTS describes this
    shared 1.2 V rail as vdd-hba-supply = <&vreg_l9b_1p2>.

    This is separate from the PHY rails on sheet 13: P24 UFS core uses
    VREG_L10C_0P88 and P22 UFS 1.2 V circuits use VREG_L6B_1P2.
    The board-wide VCC_1V8 powers peripheral level translators and is
    not a substitute for the UFS host-pad rail.

    Radxa linux-7.0.11 at c875d59793d5 leaves vdd-hba unspecified; the
    generic UFS driver treats an absent property as always enabled and
    emits an informational message. The new description follows the
    schematic, not an attempt to hide that message. It does not change
    PHY voltage policy, device VCC/VCCQ/VCCQ2 or the Rate-A limitation,
    and it is not claimed to fix reported UFS hibernation/reset faults.

    Schematic: https://dl.radxa.com/dragon/q6a/hw/radxa_dragon_q6a_schematic_v1.21.pdf
    Pin definitions: QCS6490/QCS5430 Data Sheet 80-23889-1 Rev. AW, Table 2-4.
    The same host-pad modelling pattern is used by upstream commit
    2c20c75d8505 for SM8350 HDK; the Q6A connection was checked separately.

  Firmware and userspace
    Firmware, bootloaders, root filesystems and proprietary userspace are
    not bundled into this GPL kernel source tree. Install the appropriate
    linux-firmware/vendor package before testing a board.

    The AIC D80 loader expects aic8800d80/{fw_adid_8800d80_u02.bin,
    fw_patch_8800d80_u02.bin,fw_patch_table_8800d80_u02.bin,
    fmacfw_8800d80_u02.bin} under /lib/firmware. Radxa's package uses
    aic8800_fw/SDIO/aic8800D80; a distribution can map that directory to
    the driver's expected name. ZERO 3W UART Bluetooth additionally needs
    HCI attachment after the SDIO firmware has loaded, for example:
      hciattach -s 1500000 /dev/ttyS1 any 1500000 flow nosleep
    AP6212 uses brcmfmac firmware plus board NVRAM and its serdev Bluetooth
    firmware instead; do not apply the AIC attachment command to that DTB.

    Older Realtek-equipped LicheeRV boards use rtl8733bs and btrtksdio,
    selected by their SDIO IDs rather than by an AIC compatibility shim.
    Bluetooth requires rtl_bt/rtl8821ds_fw and rtl_bt/rtl8821ds_config.
    Sophgo MPI/NPU libraries, sensor tuning files and codec firmware remain
    userspace dependencies described in drivers/staging/sophgo/README.
    C906 userspace built with modern GCC needs -mno-fence-tso or firmware
    with suitable illegal-instruction emulation. The kernel disables GCC's
    fence.tso emission when T-HEAD errata support is selected.

    Q8B needs board-specific ADSP/topology files under
    qcom/sc8280xp/radxa/dragon-q8b, the Iris firmware named by its DT and
    firmware for the installed M.2 card. The carried audio loader expects
    qcom/sc8280xp/SC8280XP-Radxa-Dragon-Q8B-tplg.bin; distributors must map
    the packaged topology to that path. The NSP0 path in the DT likewise
    requires an appropriate board-compatible CDSP image, not a guessed blob.

    Nix configuration pins and deployed devices are not changed by a source
    branch update. Update the consumer's source hash, kernel/module release
    and firmware set together, then perform physical boot and peripheral
    acceptance before deployment.

    The existing A7A deployment expects an embedded initramfs. Retain that
    consumer configuration and its measured boot arguments; a standalone
    source-tree Image is not a replacement for the complete Nix boot image.

  v7.3.4 verification
    Code revision: 6c89b2f5596eacf64484b56470ac6ec8e36c871d.
    Q8B: Image, all selected modules and Qualcomm DTBs built with GCC 16.2;
    affected DTBs were rebuilt after removing the duplicate IOVA reservations.
    ZERO 3W: Image, all selected modules and the original/AP6212/AIC8800DS2
    DTBs built. A733: Image, all selected modules and A7A/A7S/A7Z DTBs built.
    LicheeRV: Image, all selected modules, B/E/W/WE DTBs and all three
    precomposed touchscreen DTBs built with GCC 16.2.
    Q6A/CM-Q64: ordinary/KVM DTBs and the optional Q6A headless DTB built.
    The Q6A GPU-only MSM and USB AIC driver objects also built successfully.
    NanoPC-T4: base DTB, HD702E overlay and composed DTB built.
    All six configurations report kernel.release 7.3.4. ELF architecture checks
    passed for the four vmlinux files; six representative TC956x, AIC, Btrfs,
    Sophgo ION and Realtek modules have matching 7.3.4 vermagic. olddefconfig
    retained boot-storage, Q8B power sequencing/TC956x, Q6A KMS-off, wireless
    variant and Sophgo multimedia selections.

    Compiled-DTB comparisons show that Q6A headless changes only sound,
    wcd938x and q6apm status relative to the KVM DTB. Each LicheeRV touch
    variant enables exactly its selected controller and changes no other
    property relative to the WE base DTB.
    All seven Q8B/Q6A/CM-Q64 ordinary, EL2, KVM and headless DTBs were checked
    for removal of the duplicate Iris IOVA reservation, retaining exactly the
    previous firmware name, physical carveout range and no-map attribute.
    For multiple top-level DTB goals sharing a base, use -j1; alternatively
    use the single dtbs goal with parallel jobs. Separate recursive top-level
    goals can otherwise race over the same generated dependency file.

    Hardware boot and peripheral operation remain unvalidated. Existing
    vendor/staging warnings are not suppressed or treated as hardware proof.

  Previous v7.3.3 verification (not a v7.3.4 build result)
    GCC 16.2 cross-builds, with kernel.release checked as 7.3.3:
      Q8B profile       Image, modules and Qualcomm DTBs passed
      ZERO 3W profile   Image, modules and three ZERO 3W DTBs passed
      A733 BSP profile  Image, modules and A7A/A7S/A7Z DTBs passed
      LicheeRV profile  Image, all selected modules and B/E/W/WE DTBs passed

    Q6A/CM-Q64 configurations, ordinary/KVM DTBs, USB AIC objects and the
    Q6A headless MSM path were checked separately. NanoPC-T4 configuration
    and DTB passed; its mainline drivers are also covered by the Rockchip
    build. No separate full NanoPC-T4 or Q6A Image build is claimed here.

    The three LicheeRV touch overlays were compiled/applied and their
    decoded DTBs checked to enable exactly one controller. Changed binding
    meta-schemas and selected board/peripheral DT schemas were checked
    with dtschema 2026.9. Vendor BSP DTBs and staging drivers still produce
    inherited warnings; this is not a warning-free upstream-quality claim.

    Physical boot and full peripheral acceptance were NOT performed. In
    particular, compilation does not prove DMA/IOMMU behaviour, storage
    reliability, radio operation, display timing or multimedia/TPU output.

  Trademark notice
    Linux® is the registered trademark of Linus Torvalds in the U.S. and other
    countries. This repository is not endorsed by Linus Torvalds, the Linux
    Foundation, Radxa, Qualcomm, Linaro, or any other rights holder named in
    the source tree. Use at your own risk.

  License
    Inherits GPL-2.0 WITH Linux-syscall-note from upstream Linux (see COPYING
    and LICENSES/). Original SPDX-License-Identifier headers and copyright
    lines are preserved unchanged. Additions made under honsunrise's own name
    are released under GPL-2.0 unless a per-file SPDX header states otherwise.

  Historical v7.2.10 integration
    - Merge v7.2.10, retaining the complete v7.1 vendor ancestry and its
      original authors, licenses and DCO trailers; no vendor-history rebase.
    - Preserve Q6A/CM-Q64 PCIe bus-topology mappings while adding the missing
      SMMU mask cells, following upstream Q6A fix efcf504642bae.
    - Preserve SC8280XP thermal sensors, PCI bridge-only PERST parsing and
      externally preloaded remoteproc support. Combine remoteproc attachment
      with upstream handover-IRQ balancing and stopped-subsystem detection.
    - Adapt carried DP CEC to upstream's threaded-IRQ/plugged lifecycle and
      retain Radxa panel timing and bridge support. Upstream 5e97d117b79c3
      supersedes the carried PUSH_IDLE fix; 96379c2dec725 supplies the
      cached-EDID fix. The previously omitted 15 patches below remain omitted.
    - Reconcile Iris with upstream platform/firmware and encoder refactors,
      retaining SC8280XP, Gen1/Gen2 firmware fallback, SFR reporting and HEVC
      alignment. Retain upstream GOP fix cfcaa26b36f7e and runtime-PM fixes.
    - Upstream now supplies UFS active-lane validation, including the PCI
      unset-lane guard, and asynchronous remoteproc attachment; retain these
      implementations rather than duplicate the carried backports.
    - Restore the SC8280XP video node's original Radxa includes:
      clock/qcom,sm8350-videocc.h, reset/qcom,sm8350-videocc.h and
      interconnect/qcom,icc.h. SC8280XP uses videocc-sm8350.c; there is no
      separate qcom,videocc-sc8280xp.h to import. Do not skip SC8280XP,
      SA8540P, SA8295P or Dragon Q8B DTBs to conceal missing bindings.

  Initial integration build / review follow-up
    - The first downstream Nix build exposed an unresolved pil_video_mem
      phandle and the vendor OTA7290B panel's removed drm_panel_init API.
      SC8280XP's disabled SoC video node no longer references board-owned
      memory. Dragon Q8B retains its existing 0x8c600000 firmware carveout,
      IOVA reservation and enabled Iris node; its obsolete inherited-region
      deletion is removed. No other board's memory address is inferred.
    - OTA7290B now uses devm_drm_panel_alloc, matching the upstream refcounted
      panel lifecycle, with its explicit registration/removal and DSI
      attach-failure unwind retained.
    - Qualcomm's hardware SID programmer now follows provider #iommu-cells,
      including the OF parser's legacy four-cell rule, rather than assuming
      every iommu-map tuple has four cells. It retains supported RID ranges,
      map-mask aliases and CRC8 collision chaining without copying the map
      or scanning the complete RID space.
    - Iris IRQ-depth and core-mutex ordering are fixed by 0d36bc055e78,
      covering init/deinit as well as suspend/resume. That commit alone
      does not fix the runtime-PM dependency: Gen1 responses can submit
      commands requiring PM, and IRQ handlers can also wait for inst->lock
      held by ordinary PM-owning command submitters.
    - Runtime suspend therefore uses disable_hardirq to detect active IRQ
      threads without waiting for them. If one is active, it balances the
      temporary disable and returns -EAGAIN without touching power. Once no
      handler is active and the IRQ is disabled, synchronize_irq completes
      full quiescence before the existing locked power-off sequence.
      Commands and responses retain their normal PM ownership; a failed
      pm_runtime_resume_and_get no longer incorrectly drops a reference.
      Port this follow-up together with 0d36bc055e78, not that commit alone.
    - Successful PAS attachment records its resource lifecycle independently
      of rproc->state. Stop disables the attached handover IRQ without
      unpreparing load-state/interconnect resources it never acquired,
      including subdevice-start unwind and crash recovery. Externally
      preloaded firmware remains externally owned.

  Build / downstream interface
    - Source release is 7.3.4 (EXTRAVERSION empty). Downstream source-archive
      builds must use version/modDirVersion 7.3.4, CONFIG_LOCALVERSION=""
      and CONFIG_LOCALVERSION_AUTO=n; update the source revision/hash and
      remove skip-sc8280xp-dtbs.patch.
    - Existing Q6A deployments must retain their headless configuration:
      CONFIG_DRM_MSM=m and CONFIG_DRM_MSM_KMS=n. Enabling KMS previously
      caused a DP IRQ storm. Q8B has a separate display-enabled profile;
      its display configuration is not a replacement for the Q6A profile.
    - Preserve CONFIG_EFI=y, CONFIG_EFI_STUB=y, CONFIG_KVM=y and built-in
      CONFIG_SCSI_UFSHCD/CONFIG_SCSI_UFSHCD_PLATFORM/CONFIG_SCSI_UFS_QCOM.
      No new explicit config selection is needed for these paths. Iris
      selects QCOM_UBWC_CONFIG; SC_VIDEOCC_7280 serves Q6A and SM_VIDEOCC_8350
      serves SC8280XP.
    - ARCH_QCOM builds qcom/qcs6490-radxa-dragon-q6a.dtb and
      qcom/qcs6490-radxa-dragon-q6a-kvm.dtb. The latter combines the base DTB
      with qcs6490-radxa-dragon-q6a-kvm.dtbo, retaining radxa,enable-kvm,
      EL2 GPU setup, remoteproc broken-reset and SCM shared-memory ownership.
    - The optional qcs6490-radxa-dragon-q6a-kvm-headless.dtb composes that
      same base and KVM overlay with qcs6490-radxa-dragon-q6a-headless.dtbo.
      It does not duplicate KVM/display flags or board regulator definitions.
      All three DTBs were built and decoded for this follow-up; changed
      regulator and headless-profile runtime behaviour is not yet validated.
    - Validate the configured kernel/modules, all selected Q6A DTBs and the formerly
      skipped SC8280XP family in the consuming Nix configuration after each
      source update. Physical EFI boot, UFS I/O, Iris PM and KVM require
      separate hardware validation before deployment; compilation alone does
      not establish those properties.

  Manually ported / synced across v7.0.11 → v7.1.y
    Group A: Radxa CM-Q64 board support
      - arm64: dts: qcom: add Radxa CM-Q64 on RPi CM5 IO carrier board
      - arm64: dts: qcom: radxa-cm-q64-rpi-cm5-io: move fan PWM
      - arm64: dts: qcom: radxa-cm-q64: disabled DP0 Playback
      - arm64: dts: qcom: radxa-cm-q64: set uart5_tx output-high
      - firmware: qcom: scm: Allow QSEECOM for Radxa CM-Q64
    Group B: SCM storage interface
      - firmware: qcom: scm: Add SCM storage interface support
      - firmware: qcom: scm: Add Radxa Dragon Q8B to SCM storage allowlist
    Group C: Lontium LT8712SX bridge driver
      - drm/bridge: lt8712: Add Lontium LT8712sx bridge driver
    Group D (partial): DP CEC
      - drm/msm/dp: add DisplayPort CEC-Tunneling-over-AUX support
      - (fixup) drm/msm/dp: Add DisplayPort CEC tunneling over AUX support
      - drm/msm/dp: Keep branch sink count in sync
    Group E: Radxa 7.0.11-2 sync
      - arm64: dts: qcom: Mark eeprom read-only for Dragon Q8B
      - arm64: dts: qcom: qcs6490-radxa-cm-q64: Switch to use Iris HFI Gen2 firmware
      - fixup! arm64: dts: qcom: sc8280xp: add missing QUP pinctrl states
      - arm64: dts: qcom: sc8280xp: move UART2 pinctrl to SoC dtsi
      - arm64: dts: qcom: sc8280xp: Add missing QUP UART nodes
      - arm64: dts: qcom: sc8280xp: Fix DWC3 core register size
      - wip: drm/msm/dpu: Prevent unnecessary hardware block migration during hot-unplug

    Already upstream in v7.1.2
      - spi: qcom-geni: Fix cs_change handling on the last transfer


  Historical omissions during v7.1 forwarding (15 vendor commits)
    These exact Radxa commits were not forwarded because the upstream
    DP/q6apm interfaces had changed. They are listed for provenance, not
    as an assertion that Linux 7.3 lacks every corresponding feature.
    Newer upstream implementations are retained; physical DSC, HDR,
    colour-space and hotplug behaviour still requires board/sink testing.

      drm/msm/dp: Read sink DSC and FEC capabilities
      drm/msm/dp: Add helpers to select DSC configurations
      drm/msm/dp: Program DSC PPS, DTO and FEC
      drm/msm: Enable DisplayPort DSC
      drm/msm/dp: Handle IRQ HPD as a sink request
      drm/msm/dp: Mark the link bad when an active sink is replugged
      drm/msm/dp: Send VSC SDP for BT.2020 RGB
      drm/msm/dp: Program static HDR metadata SDP
      drm/msm/dp: Expose HDR output metadata on DP
      drm/msm/dp: Add max bpc support
      drm/msm/dp: Support DCI-P3 RGB colorspace
      drm/msm/dp: Request peripheral flush for VSC colorimetry
      drm/msm/dp: avoid redundant HPD bridge notifications
      drm/msm/dp: recover link on replug when userspace may skip modeset
      Revert "ASoC: qcom: q6apm: Add support for early buffer mapping on DSP"

  Not redistributed in this fork (intentionally dropped from Radxa branch)
    - 3 historical work-in-progress commits: "wip: q8b: flattened usb",
      "Revert \"wip: q8b: flattened usb\"", "wip: firmware: qcom: tzmem"
    - 1 Radxa 7.0.11-2 downstream HACK not reauthored for v7.1.y:
      "HACK: disable fake battery device on pmic-glink"
    - 2 packaging commits: "scripts: Add PKGBUILD ...",
      "scripts: PKGBUILD-radxa: Build separate dtbs package"

  Reporting issues
    https://github.com/honsunrise/linux/issues
