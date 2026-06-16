This repository is an UNOFFICIAL fork of the Linux kernel.

  Upstream base : Linux stable v7.1  (commit 8cd9520d35a6)
  Vendor source : https://github.com/radxa/kernel  branch linux-7.0.11  (commit 6e8b6eed39ab)
  Forwarded to  : v7.1  (in branch honsunrise/v7.1)

  Pipeline      : Radxa  (300 vendor commits on stable v7.0.11)
                  → drop noise   (-3 wip, -2 PKGBUILD)
                  → rebase --signoff onto stable v7.1, --empty=drop
                  → 247 commits auto-rebased (12 detected empty, 36 conflict-skipped)
                  → manual cherry-pick of 11 high-value Radxa-own commits
                  → 258 vendor commits (this branch)

  Every commit carries DCO Signed-off-by:
      - original author (preserved verbatim)
      - Honsun Zhu <honsun@linux.com>  (forwarder)

  Branches (all visible at github.com/honsunrise/linux):
    master                       upstream Linus mainline (mirror)
    linux-7.0.y                  stable v7.0.y series (mirror)
    linux-7.1.y                  stable v7.1.y series (mirror, this branch's base)
    radxa-original/linux-7.0.11  Radxa vendor untouched (mirror, reference)
    honsunrise/v7.1              this fork's main branch

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

  Manually ported across v7.0.11 → v7.1 (11 commits)
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

  Needs-rewrite for v7.1 (15 commits, NOT in this branch)
    The drm/msm/dp subsystem and qcom q6apm were substantially reworked in
    upstream v7.1, in ways that invalidate the assumptions of these Radxa
    patches (touched functions deleted, struct layouts changed, lifecycle
    hooks moved). Rather than risk a wrong port, they are intentionally
    omitted; each must be reauthored against the v7.1 design.

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
    - 3 work-in-progress commits: "wip: q8b: flattened usb",
      "Revert \"wip: q8b: flattened usb\"", "wip: firmware: qcom: tzmem"
    - 2 packaging commits: "scripts: Add PKGBUILD ...",
      "scripts: PKGBUILD-radxa: Build separate dtbs package"

  Reporting issues
    https://github.com/honsunrise/linux/issues
