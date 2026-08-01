#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin wifi-bluetooth.sh
a733_require_command jq lsusb iw btmgmt rfkill journalctl ip tee timeout

lsusb -d a69c:8d80 >/dev/null || a733_block "AIC8800 USB a69c:8d80 is absent"
for module in aic_load_fw aic8800_fdrv; do
	grep -q "^$module " /proc/modules || a733_fail "$module is not loaded"
done
interface=${A733_WIFI_INTERFACE:-wlan0}
ip link show "$interface" >/dev/null 2>&1 || a733_fail "$interface is absent"
rfkill unblock wifi
scan="$A733_TMPDIR/scan.txt"
sudo iw dev "$interface" scan | tee "$scan" >/dev/null
grep -q '^BSS ' "$scan" || a733_fail "Wi-Fi scan returned no BSS"
if [ -n "${A733_WIFI_SOAK_COMMAND:-}" ]; then
	timeout 3600 sh -c "$A733_WIFI_SOAK_COMMAND" >"$A733_TMPDIR/wifi-soak.txt" 2>&1
else
	a733_block "set A733_WIFI_SOAK_COMMAND for one-hour connected transfer"
fi
rfkill unblock bluetooth
btmgmt power on >"$A733_TMPDIR/bt-power.txt"
if [ -n "${A733_BLUETOOTH_PEER_COMMAND:-}" ]; then
	sh -c "$A733_BLUETOOTH_PEER_COMMAND" >"$A733_TMPDIR/bluetooth.txt"
else
	a733_block "set A733_BLUETOOTH_PEER_COMMAND for pairing and data exchange"
fi
if [ -n "${A733_RADIO_SUSPEND_COMMAND:-}" ]; then
	sh -c "$A733_RADIO_SUSPEND_COMMAND" >"$A733_TMPDIR/suspend.txt"
else
	a733_block "set A733_RADIO_SUSPEND_COMMAND for reboot/suspend power sequencing"
fi
radio_errors='aic8800.*(crash|timeout|error)|Bluetooth.*(timeout|error)'
if journalctl -k --since "$A733_STARTED_AT" |
	grep -Ei "$radio_errors" >"$A733_TMPDIR/kernel-errors.txt"; then
	a733_fail "radio errors appeared in kernel log"
fi
a733_metric_json bss_count "$(grep -c '^BSS ' "$scan")"
a733_add_check usb-bind pass a69c:8d80
a733_add_check wifi pass "scan and one-hour transfer"
a733_add_check bluetooth pass "pair and exchange"
a733_add_check suspend-resume pass radio
a733_pass
