#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin serial-ramoops-watchdog.sh
a733_require_command jq systemctl journalctl findmnt

if [[ $(uname -r) == *aw2511* ]]; then
	default_serial_getty=serial-getty@ttyAS0.service
else
	default_serial_getty=serial-getty@ttyS0.service
fi
serial_unit=${A733_SERIAL_GETTY:-$default_serial_getty}
systemctl is-active --quiet "$serial_unit" || a733_fail "$serial_unit is not active"
[ -d /sys/fs/pstore ] || a733_fail "/sys/fs/pstore is absent"
watchdog_device=${A733_WATCHDOG_DEVICE:-/dev/watchdog0}
[ -c "$watchdog_device" ] || a733_fail "$watchdog_device is absent"
watchdog_identity=$(cat /sys/class/watchdog/watchdog0/identity)
bootstatus=$(cat /sys/class/watchdog/watchdog0/bootstatus)

a733_metric_string serial_unit "$serial_unit"
a733_metric_string watchdog_identity "$watchdog_identity"
a733_metric_string watchdog_bootstatus "$bootstatus"
a733_metric_json pstore_file_count "$(find /sys/fs/pstore -maxdepth 1 -type f | wc -l)"
a733_add_check serial-getty pass "$serial_unit"
a733_add_check ramoops pass "/sys/fs/pstore present"
a733_add_check watchdog-probe pass "$watchdog_identity"

if [ "${A733_ARM_WATCHDOG:-0}" != 1 ]; then
	a733_block "set A733_ARM_WATCHDOG=1 with a recovery operator present"
fi
sync
for mount in $(findmnt -rn -o TARGET); do
	sync -f "$mount" 2>/dev/null || true
done
if command -v wdctl >/dev/null 2>&1; then
	wdctl --settimeout 30 "$watchdog_device"
fi
python3 - "$watchdog_device" <<'PY'
import os,sys,time
fd=os.open(sys.argv[1],os.O_WRONLY)
time.sleep(60)
os.close(fd)
raise SystemExit("watchdog did not reset the board")
PY
a733_fail "watchdog did not reset the board"
