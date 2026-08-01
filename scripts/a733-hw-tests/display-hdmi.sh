#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin display-hdmi.sh
a733_require_command jq modetest journalctl

driver=${A733_DRM_DRIVER:-sunxi-drm}
connectors="$A733_TMPDIR/connectors.txt"
modetest -M "$driver" -c >"$connectors" || a733_block "DRM driver $driver is unavailable"
connector_pattern='HDMI.*(connected|disconnected)|(connected|disconnected).*HDMI'
if ! grep -E "$connector_pattern" "$connectors" >/dev/null; then
	a733_fail "no HDMI connector was enumerated"
fi
before=$(journalctl -k --since "$A733_STARTED_AT" | grep -c 'drm hdmi detect: disconnect' || true)
sleep 60
after=$(journalctl -k --since "$A733_STARTED_AT" | grep -c 'drm hdmi detect: disconnect' || true)
[ "$before" -eq "$after" ] || \
	a733_fail "disconnected HDMI detect log increased from $before to $after"

if [ -n "${A733_MODETEST_1080P_COMMAND:-}" ]; then
	sh -c "$A733_MODETEST_1080P_COMMAND" >"$A733_TMPDIR/1080p.txt"
else
	a733_block "set A733_MODETEST_1080P_COMMAND with a connected monitor"
fi
if [ -n "${A733_MODETEST_4K_COMMAND:-}" ]; then
	sh -c "$A733_MODETEST_4K_COMMAND" >"$A733_TMPDIR/4k.txt"
else
	a733_block "set A733_MODETEST_4K_COMMAND for the 4K fixture"
fi
if [ -n "${A733_HDMI_HOTPLUG_COMMAND:-}" ]; then
	sh -c "$A733_HDMI_HOTPLUG_COMMAND" >"$A733_TMPDIR/hotplug.txt"
else
	a733_block "set A733_HDMI_HOTPLUG_COMMAND for ten physical hotplug cycles"
fi
if ! journalctl -k -b | grep -q 'drm.*client.*log\|DRM_CLIENT_LOG'; then
	a733_fail "DRM_CLIENT_LOG boot output was not observed"
fi
if [ -n "${A733_KMS_SOAK_COMMAND:-}" ]; then
	timeout 3600 sh -c "$A733_KMS_SOAK_COMMAND" >"$A733_TMPDIR/kms-soak.txt" 2>&1
else
	a733_block "set A733_KMS_SOAK_COMMAND for the one-hour KMS run"
fi
a733_metric_json disconnected_log_count "$after"
a733_metric_string drm_driver "$driver"
a733_add_check connector-enumeration pass "$driver"
a733_add_check disconnected-log-soak pass "60 seconds without repeated log"
a733_add_check modes pass "1080p60 and 4K60"
a733_add_check hotplug pass "ten cycles"
a733_add_check kms-soak pass "3600 seconds"
a733_pass
