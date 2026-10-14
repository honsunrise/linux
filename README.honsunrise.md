This repository is an UNOFFICIAL fork of the Linux kernel.

  Upstream base : Linux stable v7.2.10 (commit 7b20d05fd38d)
  Vendor source : https://github.com/radxa/kernel  branch linux-7.0.11  (commit 922ecc5644d9)
  Forwarded to  : v7.2.y  (in branch honsunrise/v7.2)

  Pipeline      : Radxa  (309 vendor commits on stable v7.0.11)
                  → drop noise   (-3 historical wip, -1 pmic-glink HACK, -2 PKGBUILD)
                  → rebase --signoff onto stable v7.1.2, --empty=drop
                  → keep the existing v7.1 forward-port and refresh the stable base
                  → sync Radxa 7.0.11-2 delta: 7 ported, 1 already upstream, 1 HACK omitted
                  → 263 carried vendor commits at v7.1 HEAD 2ca9a714e4e3
                  → merge stable v7.2.10 without rewriting vendor history

  Vendor forwarding commits carry DCO Signed-off-by:
      - original author (preserved verbatim)
      - Honsun Zhu <honsun@linux.com>  (forwarder)

  Branches (all visible at github.com/honsunrise/linux):
    master                       upstream Linus mainline (mirror)
    linux-7.0.y                  stable v7.0.y series (mirror)
    linux-7.1.y                  stable v7.1.y series (mirror, previous base)
    radxa-original/linux-7.0.11  Radxa vendor untouched (mirror, reference)
    honsunrise/v7.1              preserved v7.1 forward-port
    honsunrise/v7.2              this fork's v7.2 stable integration branch

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

  v7.2.10 integration
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
    - Source release is 7.2.10 (EXTRAVERSION empty). Downstream source-archive
      builds must use version/modDirVersion 7.2.10, CONFIG_LOCALVERSION=""
      and CONFIG_LOCALVERSION_AUTO=n; update the source revision/hash and
      remove skip-sc8280xp-dtbs.patch.
    - Keep the existing headless config, not a replacement defconfig:
      CONFIG_DRM_MSM=m and CONFIG_DRM_MSM_KMS=n. Enabling KMS previously
      caused a DP IRQ storm on the deployed Q6A; no display enablement is
      implied by carrying these display driver changes.
    - Preserve CONFIG_EFI=y, CONFIG_EFI_STUB=y, CONFIG_KVM=y and built-in
      CONFIG_SCSI_UFSHCD/CONFIG_SCSI_UFSHCD_PLATFORM/CONFIG_SCSI_UFS_QCOM.
      No new explicit config selection is needed for these paths. Iris
      selects QCOM_UBWC_CONFIG; SC_VIDEOCC_7280 serves Q6A and SM_VIDEOCC_8350
      serves SC8280XP.
    - ARCH_QCOM builds qcom/qcs6490-radxa-dragon-q6a.dtb and
      qcom/qcs6490-radxa-dragon-q6a-kvm.dtb. The latter combines the base DTB
      with qcs6490-radxa-dragon-q6a-kvm.dtbo, retaining radxa,enable-kvm,
      EL2 GPU setup, remoteproc broken-reset and SCM shared-memory ownership.
    - Validate the configured kernel/modules, both Q6A DTBs and the formerly
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


  Needs-rewrite since v7.1 (15 commits, NOT ported into this branch)
    The drm/msm/dp subsystem and qcom q6apm were substantially reworked in
    upstream v7.1, in ways that invalidate the assumptions of these Radxa
    patches (touched functions deleted, struct layouts changed, lifecycle
    hooks moved). Rather than risk a wrong port, they are intentionally
    omitted; each needs an independent port against the current design.

    Effect: DisplayPort DSC compression, DP HDR metadata SDP, DP color
    spaces (BT.2020 / DCI-P3), max bpc selection, peripheral flush for
    VSC colorimetry, IRQ HPD as sink request, sink-replug bad-link
    marking, redundant HPD-bridge notification suppression, replug
    recovery, sink DSC/FEC cap caching, and the q6apm early-buffer-mapping
    revert are all currently unavailable.

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
