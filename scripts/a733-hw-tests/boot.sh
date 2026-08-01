#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin boot.sh
a733_require_command jq findmnt systemctl nproc

kernelrelease=$(uname -r)
compatibles=$(tr '\0' '\n' </sys/firmware/devicetree/base/compatible)
root_source=$(findmnt -n -o SOURCE /)
root_fstype=$(findmnt -n -o FSTYPE /)
root_options=$(findmnt -n -o OPTIONS /)
system_state=$(systemctl is-system-running 2>/dev/null || true)
cpu_count=$(nproc)

a733_metric_string kernelrelease "$kernelrelease"
a733_metric_string compatibles "$compatibles"
a733_metric_string root_source "$root_source"
a733_metric_string root_fstype "$root_fstype"
a733_metric_string root_options "$root_options"
a733_metric_string system_state "$system_state"
a733_metric_json cpu_count "$cpu_count"

if [ "$cpu_count" -ne 8 ]; then
	a733_fail "expected eight CPUs, found $cpu_count"
fi
if [ "$root_fstype" != "btrfs" ]; then
	a733_fail "root filesystem is not Btrfs: $root_fstype"
fi
case "$system_state" in
	running | degraded) ;;
	*) a733_fail "system state is $system_state" ;;
esac
if [ -n "${A733_EXPECT_KERNEL:-}" ] && [ "$kernelrelease" != "$A733_EXPECT_KERNEL" ]; then
	a733_fail "kernelrelease $kernelrelease != $A733_EXPECT_KERNEL"
fi
if [ -n "${A733_EXPECT_COMPATIBLES:-}" ]; then
	old_ifs=$IFS
	IFS=,
	for compatible in $A733_EXPECT_COMPATIBLES; do
		if ! printf '%s\n' "$compatibles" | grep -Fx "$compatible" >/dev/null; then
			a733_fail "missing compatible: $compatible"
		fi
	done
	IFS=$old_ifs
fi

a733_add_check cpu-topology pass "8 CPUs online"
a733_add_check root-filesystem pass "$root_source $root_fstype"
a733_add_check system-state pass "$system_state"
a733_pass
