#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

A733_SCHEMA_VERSION=1
A733_FINISHED=0

_a733_json_string() {
	jq -Rn --arg value "$1" '$value'
}

a733_begin() {
	A733_TEST_ID=$1
	A733_STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	A733_OUTPUT=${A733_OUTPUT:-"$PWD/${A733_TEST_ID%.sh}.json"}
	A733_CANDIDATE_ID=${A733_CANDIDATE_ID:-vendor-6.6}
	A733_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/a733-${A733_TEST_ID%.sh}.XXXXXX")
	A733_CHECKS="$A733_TMPDIR/checks.jsonl"
	A733_METRICS="$A733_TMPDIR/metrics.json"
	: >"$A733_CHECKS"
	printf '{}\n' >"$A733_METRICS"
	trap 'a733_cleanup $?' EXIT INT TERM
}

a733_cleanup() {
	code=$1
	if [ "${A733_FINISHED:-0}" -eq 0 ]; then
		set +e
		a733_finish fail "test exited unexpectedly with status $code" "$code"
	fi
	rm -rf "${A733_TMPDIR:-}"
}

a733_add_check() {
	name=$1
	status=$2
	details=${3:-}
	jq -cn \
		--arg name "$name" \
		--arg status "$status" \
		--arg details "$details" \
		'{name:$name,status:$status,details:$details}' >>"$A733_CHECKS"
}

a733_metric_string() {
	key=$1
	value=$2
	tmp="$A733_TMPDIR/metrics.next"
	jq --arg key "$key" --arg value "$value" '.[$key]=$value' \
		"$A733_METRICS" >"$tmp"
	mv "$tmp" "$A733_METRICS"
}

a733_metric_json() {
	key=$1
	value=$2
	tmp="$A733_TMPDIR/metrics.next"
	jq --arg key "$key" --argjson value "$value" '.[$key]=$value' \
		"$A733_METRICS" >"$tmp"
	mv "$tmp" "$A733_METRICS"
}

a733_require_command() {
	for command_name in "$@"; do
		if ! command -v "$command_name" >/dev/null 2>&1; then
			a733_block "required command is unavailable: $command_name"
		fi
	done
}

a733_require_regular_target() {
	target=$1
	expected_mount=$2

	if [ -b "$target" ]; then
		a733_fail "refusing block-device target: $target"
	fi
	if [ -L "$target" ]; then
		a733_fail "refusing symlink target: $target"
	fi
	if [ -e "$target" ] && [ ! -f "$target" ]; then
		a733_fail "target exists but is not a regular file: $target"
	fi
	mount_real=$(realpath "$expected_mount")
	parent_real=$(realpath "$(dirname "$target")")
	case "$parent_real/" in
		"$mount_real/" | "$mount_real"/*/) ;;
		*) a733_fail "target escapes expected mount: $target" ;;
	esac
	actual_mount=$(findmnt -n -o TARGET -T "$(dirname "$target")")
	actual_mount_real=$(realpath "$actual_mount")
	if [ "$actual_mount_real" != "$mount_real" ]; then
		a733_fail "target mount $actual_mount_real differs from $mount_real"
	fi
}

a733_finish() {
	status=$1
	reason=${2:-}
	exit_code=${3:-0}
	A733_FINISHED=1
	finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	output_dir=$(dirname "$A733_OUTPUT")
	mkdir -p "$output_dir"
	tmp_output=$(mktemp "$output_dir/.${A733_TEST_ID%.sh}.XXXXXX")
	jq -s \
		--argjson schema_version "$A733_SCHEMA_VERSION" \
		--arg test_id "$A733_TEST_ID" \
		--arg status "$status" \
		--arg candidate_id "$A733_CANDIDATE_ID" \
		--arg kernelrelease "$(uname -r)" \
		--arg started_at "$A733_STARTED_AT" \
		--arg finished_at "$finished_at" \
		--arg reason "$reason" \
		--slurpfile metrics "$A733_METRICS" \
		'{
			schema_version: $schema_version,
			test_id: $test_id,
			status: $status,
			candidate_id: $candidate_id,
			kernelrelease: $kernelrelease,
			started_at: $started_at,
			finished_at: $finished_at,
			reason: $reason,
			checks: ., metrics: $metrics[0]
		}' \
		"$A733_CHECKS" >"$tmp_output"
	chmod 0444 "$tmp_output"
	mv -f "$tmp_output" "$A733_OUTPUT"
	exit "$exit_code"
}

a733_pass() {
	a733_finish pass "${1:-}" 0
}

a733_not_applicable() {
	a733_finish not-applicable "$1" 0
}

a733_block() {
	a733_finish blocked "$1" 2
}

a733_fail() {
	a733_finish fail "$1" 1
}
