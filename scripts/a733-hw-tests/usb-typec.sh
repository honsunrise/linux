#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin usb-typec.sh
a733_require_command jq lsusb journalctl

usb2_id=${A733_USB2_FIXTURE_ID:-}
usb3_id=${A733_USB3_FIXTURE_ID:-}
[ -n "$usb2_id" ] || a733_block "set A733_USB2_FIXTURE_ID for the USB2 fixture"
[ -n "$usb3_id" ] || a733_block "set A733_USB3_FIXTURE_ID for the USB3 fixture"
lsusb -d "$usb2_id" >/dev/null || a733_fail "USB2 fixture $usb2_id is absent"
lsusb -d "$usb3_id" >/dev/null || a733_fail "USB3 fixture $usb3_id is absent"

role_path=${A733_USB_ROLE_PATH:-}
[ -n "$role_path" ] && [ -w "$role_path" ] || a733_block "set writable A733_USB_ROLE_PATH"
original_role=$(cat "$role_path")
printf device >"$role_path"
sleep 2
[ "$(cat "$role_path")" = device ] || a733_fail "failed to enter USB device role"
if [ -n "${A733_GADGET_CHECK_COMMAND:-}" ]; then
	sh -c "$A733_GADGET_CHECK_COMMAND" >"$A733_TMPDIR/gadget.txt"
else
	printf '%s' "$original_role" >"$role_path"
	a733_block "set A733_GADGET_CHECK_COMMAND for gadget enumeration"
fi
printf host >"$role_path"
sleep 2
[ "$(cat "$role_path")" = host ] || a733_fail "failed to return to USB host role"
printf '%s' "$original_role" >"$role_path"

if [ -n "${A733_TYPEC_CHECK_COMMAND:-}" ]; then
	sh -c "$A733_TYPEC_CHECK_COMMAND" >"$A733_TMPDIR/typec.txt"
else
	a733_block "set A733_TYPEC_CHECK_COMMAND for orientation, PD and mux checks"
fi
if [ -n "${A733_USB_SUSPEND_COMMAND:-}" ]; then
	sh -c "$A733_USB_SUSPEND_COMMAND" >"$A733_TMPDIR/suspend.txt"
else
	a733_block "set A733_USB_SUSPEND_COMMAND for attached-device suspend/resume"
fi
usb_errors='usb.*(disconnect.*error|reset.*failed|controller.*error)'
if journalctl -k --since "$A733_STARTED_AT" |
	grep -Ei "$usb_errors" >"$A733_TMPDIR/kernel-errors.txt"; then
	a733_fail "USB errors appeared in the kernel log"
fi
a733_metric_string usb2_fixture "$usb2_id"
a733_metric_string usb3_fixture "$usb3_id"
a733_add_check usb2 pass "$usb2_id"
a733_add_check usb3 pass "$usb3_id"
a733_add_check role-swap pass "host/device/host"
a733_add_check typec-pd pass "custom fixture check"
a733_add_check suspend-resume pass "custom fixture check"
a733_pass
