#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
output_dir=${A733_SUITE_OUTPUT_DIR:?set A733_SUITE_OUTPUT_DIR}
candidate_id=${A733_CANDIDATE_ID:-vendor-6.6}
mkdir -p "$output_dir"

if [ -n "$(find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
	echo "suite output directory is not empty: $output_dir" >&2
	exit 1
fi

default_tests="boot.sh ufs.sh gmac.sh k3s-cilium.sh
serial-ramoops-watchdog.sh clock-power-performance.sh pcie-nvme.sh
usb-typec.sh display-hdmi.sh gpu.sh npu.sh media-camera.sh audio.sh
wifi-bluetooth.sh board-io-security.sh gnss.sh remoteproc.sh"
tests=${A733_TESTS:-$default_tests}
failed=0
blocked=0
for test_id in $tests; do
	test_path="$script_dir/$test_id"
	if [ ! -x "$test_path" ]; then
		echo "missing executable test: $test_path" >&2
		exit 1
	fi
	output="$output_dir/${test_id%.sh}.json"
	set +e
	A733_OUTPUT="$output" A733_CANDIDATE_ID="$candidate_id" "$test_path"
	code=$?
	set -e
	case "$code" in
		0) ;;
		2) blocked=$((blocked + 1)) ;;
		*) failed=$((failed + 1)) ;;
	esac
done

aggregate="$output_dir/baseline.json"
tmp=$(mktemp "$output_dir/.baseline.XXXXXX")
jq -s \
	--argjson schema_version 1 \
	--arg candidate_id "$candidate_id" \
	--arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	--argjson failed "$failed" \
	--argjson blocked "$blocked" \
	'{
		schema_version: $schema_version,
		candidate_id: $candidate_id,
		generated_at: $generated_at,
		failed: $failed,
		blocked: $blocked,
		results: .
	}' \
	"$output_dir"/*.json >"$tmp"
chmod 0444 "$tmp"
mv "$tmp" "$aggregate"

if [ "$failed" -ne 0 ]; then
	exit 1
fi
