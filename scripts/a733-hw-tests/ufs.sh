#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin ufs.sh
a733_require_command jq findmnt lsblk udevadm fio btrfs journalctl realpath

root_source=$(findmnt -n -o SOURCE /)
root_device=${root_source%%\[*}
if [ ! -b "$root_device" ]; then
	a733_fail "root source is not a block device: $root_device"
fi
parent_name=$(lsblk -ndo PKNAME "$root_device")
if [ -z "$parent_name" ]; then
	a733_fail "cannot determine root parent disk for $root_device"
fi
disk="/dev/$parent_name"
model=$(lsblk -ndo MODEL "$disk" | sed 's/[[:space:]]*$//')
logical_block=$(lsblk -ndo LOG-SEC "$disk")
partition_count=$(lsblk -nrpo TYPE "$disk" | grep -c '^part$' || true)
platform_properties=$(udevadm info -q property \
	-p /sys/bus/platform/devices/4520000.ufs)
ufs_driver=$(printf '%s\n' "$platform_properties" | sed -n 's/^DRIVER=//p')
subvolumes=$(btrfs subvolume list /)
expected_driver=${A733_EXPECT_UFS_DRIVER:-}
if [ -z "$expected_driver" ]; then
	if [[ $(uname -r) == *aw2511* ]]; then
		expected_driver=sunxi-ufs-pltfm
	else
		expected_driver=sunxi-ufs-pltfrm
	fi
fi

a733_metric_string root_source "$root_source"
a733_metric_string disk "$disk"
a733_metric_string model "$model"
a733_metric_json logical_block_size "$logical_block"
a733_metric_json partition_count "$partition_count"
a733_metric_string driver "$ufs_driver"
a733_metric_string btrfs_subvolumes "$subvolumes"

if [ "$ufs_driver" != "$expected_driver" ]; then
	a733_fail "unexpected UFS platform driver: $ufs_driver"
fi
if [ -z "$subvolumes" ]; then
	a733_fail "Btrfs subvolume inventory is empty"
fi
if [ "$model" != "MT256GBCAV4U31" ]; then
	a733_fail "unexpected UFS model: $model"
fi
if [ "$logical_block" -ne 4096 ]; then
	a733_fail "unexpected UFS logical block size: $logical_block"
fi
if [ "$partition_count" -ne 3 ]; then
	a733_fail "expected three UFS partitions, found $partition_count"
fi

if [ "${A733_RUN_STORAGE_IO:-0}" != 1 ]; then
	a733_block "set A733_RUN_STORAGE_IO=1 to run the bounded UFS fio and scrub"
fi
test_mount=${A733_UFS_TEST_MOUNT:-/persistent}
test_file=${A733_UFS_TEST_FILE:-$test_mount/.a733-ufs-test}
a733_require_regular_target "$test_file" "$test_mount"
: >"$test_file"
chmod 0600 "$test_file"
trap 'code=$?; rm -f "${test_file:-}"; a733_cleanup "$code"' EXIT INT TERM
fio_json="$A733_TMPDIR/fio.json"
fio_size=${A733_FIO_SIZE:-1G}
fio_runtime=${A733_FIO_RUNTIME:-300}
fio --name=a733-ufs-test --filename="$test_file" --size="$fio_size" \
	--rw=randrw --rwmixread=70 --bs=128k --iodepth=16 --direct=1 \
	--fsync=32 --runtime="$fio_runtime" --time_based --verify=crc32c --do_verify=1 \
	--output-format=json --output="$fio_json"
sed -n '/^{/,$p' "$fio_json" >"$A733_TMPDIR/fio.clean.json"
mv "$A733_TMPDIR/fio.clean.json" "$fio_json"
verify_errors=$(jq '[.jobs[].error] | add' "$fio_json")
if [ "$verify_errors" -ne 0 ]; then
	a733_fail "fio reported errors"
fi
fio_metrics=$(jq -c '
	{jobs: [.jobs[] | {
		read_bytes: .read.io_bytes,
		write_bytes: .write.io_bytes,
		error: .error
	}]}
' "$fio_json")
a733_metric_json fio "$fio_metrics"
rm -f "$test_file"
btrfs scrub start -Bd / >"$A733_TMPDIR/scrub.txt"
storage_errors='UFS.*(reset|UIC|error)|SCSI.*error|BTRFS.*(checksum|error)'
if journalctl -k --since "$A733_STARTED_AT" |
	grep -Ei "$storage_errors" >"$A733_TMPDIR/kernel-errors.txt"; then
	a733_fail "storage errors appeared in the kernel log"
fi
a733_add_check ufs-identity pass "$model 4096-byte sectors"
a733_add_check fio-verify pass "$fio_size $fio_runtime-second crc32c verify"
a733_add_check btrfs-scrub pass "$(tr '\n' ' ' <"$A733_TMPDIR/scrub.txt")"
boot_evidence=${A733_UFS_BOOT_EVIDENCE:-}
if [ -z "$boot_evidence" ] || [ ! -f "$boot_evidence" ]; then
	a733_block "provide A733_UFS_BOOT_EVIDENCE for 10 warm and 3 cold boots"
fi
jq -e '.warm_reboots >= 10 and .cold_boots >= 3 and .storage_errors == 0' \
	"$boot_evidence" >/dev/null || a733_fail "UFS boot-cycle evidence failed"
a733_add_check boot-cycles pass "10 warm reboots and 3 cold boots"
a733_pass
