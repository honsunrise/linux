#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin pcie-nvme.sh
a733_require_command jq lspci nvme fio journalctl findmnt realpath

controller=${A733_NVME_CONTROLLER:-}
if [ -z "$controller" ]; then
	nvme_inventory=$(nvme list -o json 2>/dev/null || printf '{"Devices":[]}')
	controller=$(printf '%s' "$nvme_inventory" | jq -r '.Devices[0].DevicePath // empty')
fi
[ -n "$controller" ] || a733_block "no NVMe fixture is attached"
[ -b "$controller" ] || a733_fail "NVMe controller is not a block device: $controller"
pci_address=$(basename "$(readlink -f "/sys/class/block/$(basename "$controller")/device/device")")
link_speed=$(cat "/sys/bus/pci/devices/$pci_address/current_link_speed")
link_width=$(cat "/sys/bus/pci/devices/$pci_address/current_link_width")
a733_metric_string controller "$controller"
a733_metric_string pci_address "$pci_address"
a733_metric_string link_speed "$link_speed"
a733_metric_string link_width "$link_width"
printf '%s' "$link_speed" | grep -Eq '8\.0 GT/s|16\.0 GT/s' || \
	a733_fail "PCIe link is below Gen3: $link_speed"

if [ "${A733_RUN_PCIE_IO:-0}" != 1 ]; then
	a733_block "set A733_RUN_PCIE_IO=1 and an independent NVMe test mount"
fi
test_mount=${A733_PCIE_TEST_MOUNT:?set A733_PCIE_TEST_MOUNT}
test_file=${A733_PCIE_TEST_FILE:-$test_mount/.a733-pcie-test}
a733_require_regular_target "$test_file" "$test_mount"
: >"$test_file"
chmod 0600 "$test_file"
trap 'code=$?; rm -f "${test_file:-}"; a733_cleanup "$code"' EXIT INT TERM
fio_json="$A733_TMPDIR/fio.json"
fio_size=${A733_FIO_SIZE:-1G}
fio_runtime=${A733_FIO_RUNTIME:-300}
fio --name=a733-pcie-test --filename="$test_file" --size="$fio_size" \
	--rw=randrw --rwmixread=70 --bs=128k --iodepth=16 --direct=1 \
	--fsync=32 --runtime="$fio_runtime" --time_based --verify=crc32c --do_verify=1 \
	--output-format=json --output="$fio_json"
sed -n '/^{/,$p' "$fio_json" >"$A733_TMPDIR/fio.clean.json"
mv "$A733_TMPDIR/fio.clean.json" "$fio_json"
[ "$(jq '[.jobs[].error]|add' "$fio_json")" -eq 0 ] || a733_fail "NVMe fio failed"
pcie_errors='AER:.*error|pcie.*link down|nvme.*(reset|timeout|error)'
if journalctl -k --since "$A733_STARTED_AT" |
	grep -Ei "$pcie_errors" >"$A733_TMPDIR/kernel-errors.txt"; then
	a733_fail "PCIe/NVMe errors appeared"
fi
rm -f "$test_file"
a733_add_check pcie-link pass "$link_speed x$link_width"
a733_add_check nvme-io pass "$fio_size $fio_runtime-second crc32c verify"
if [ -z "${A733_PCIE_RESET_COMMAND:-}" ]; then
	a733_block "set A733_PCIE_RESET_COMMAND for ten link resets"
fi
sh -c "$A733_PCIE_RESET_COMMAND" >"$A733_TMPDIR/link-resets.txt"
if [ -z "${A733_PCIE_SUSPEND_COMMAND:-}" ]; then
	a733_block "set A733_PCIE_SUSPEND_COMMAND for suspend/resume"
fi
sh -c "$A733_PCIE_SUSPEND_COMMAND" >"$A733_TMPDIR/suspend.txt"
a733_add_check link-resets pass "ten resets"
a733_add_check suspend-resume pass "NVMe attached"
a733_pass
