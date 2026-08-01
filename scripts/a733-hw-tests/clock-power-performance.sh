#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin clock-power-performance.sh
a733_require_command jq stress-ng journalctl

duration=${A733_STRESS_SECONDS:-3600}
policy_count=0
opp_summary='{}'
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
	[ -d "$policy" ] || continue
	policy_count=$((policy_count + 1))
	available=$(cat "$policy/scaling_available_frequencies")
	[ -n "$available" ] || a733_fail "$policy exposes no OPP frequencies"
	name=$(basename "$policy")
	opp_summary=$(printf '%s' "$opp_summary" |
		jq --arg key "$name" --arg value "$available" '.[$key]=$value')
done
[ "$policy_count" -eq 2 ] || a733_fail "expected two cpufreq policies, found $policy_count"
[ -d /sys/class/devfreq ] || a733_fail "devfreq class is absent"
devfreq_names=$(for devfreq in /sys/class/devfreq/*; do
	[ -r "$devfreq/name" ] && cat "$devfreq/name"
done)
[ -n "$devfreq_names" ] || a733_fail "devfreq inventory is empty"
maximum_temperature() {
	for zone in /sys/class/thermal/thermal_zone*/temp; do
		cat "$zone"
	done | sort -nr | sed -n '1p'
}
stress_evidence=${A733_STRESS_EVIDENCE:-}
if [ -n "$stress_evidence" ]; then
	[ -f "$stress_evidence" ] || a733_fail "stress evidence is not a regular file"
	jq -e --argjson duration "$duration" '
		.status == "pass" and
		.metrics.duration_seconds >= $duration
	' "$stress_evidence" >/dev/null || a733_fail "stress evidence is insufficient"
	max_temp=$(jq -r '.metrics.maximum_temperature_millicelsius' "$stress_evidence")
else
	max_temp=$(maximum_temperature)
	set +e
	stress-ng --cpu 8 --vm 2 --vm-bytes 25% --timeout "${duration}s" \
		--metrics-brief >"$A733_TMPDIR/stress.txt" 2>&1 &
	stress_pid=$!
	set -e
	while kill -0 "$stress_pid" 2>/dev/null; do
		current_temp=$(maximum_temperature)
		[ "$current_temp" -le "$max_temp" ] || max_temp=$current_temp
		if [ "$max_temp" -ge 110000 ]; then
			kill "$stress_pid" 2>/dev/null || true
			wait "$stress_pid" 2>/dev/null || true
			a733_fail "temperature reached critical trip: $max_temp"
		fi
		sleep 5
	done
	set +e
	wait "$stress_pid"
	stress_status=$?
	set -e
	if [ "$stress_status" -ne 0 ]; then
		stress_tail=$(tail -n 5 "$A733_TMPDIR/stress.txt" | tr '\n' ' ')
		a733_fail "stress-ng exited $stress_status: $stress_tail"
	fi
fi
performance_errors='thermal.*(critical|shutdown)|regulator.*error'
performance_errors="$performance_errors|clk.*(failed|error)|hung task|RCU stall"
if journalctl -k --since "$A733_STARTED_AT" |
	grep -Ei "$performance_errors" >"$A733_TMPDIR/kernel-errors.txt"; then
	a733_fail "clock, regulator, thermal, or scheduler errors appeared"
fi
a733_metric_json duration_seconds "$duration"
a733_metric_json policy_count "$policy_count"
a733_metric_json cpufreq_opps "$opp_summary"
a733_metric_string devfreq_names "$devfreq_names"
a733_metric_json maximum_temperature_millicelsius "$max_temp"
a733_add_check cpufreq pass "two policies with OPP tables"
a733_add_check stress pass "${duration}s stress-ng"
a733_add_check thermal pass "maximum ${max_temp} mC"
if [ -z "${A733_OPP_TRANSITION_COMMAND:-}" ]; then
	a733_block "set A733_OPP_TRANSITION_COMMAND for every OPP and regulator voltage"
fi
sh -c "$A733_OPP_TRANSITION_COMMAND" >"$A733_TMPDIR/opp-transitions.txt"
if [ -z "${A733_PCK600_CHECK_COMMAND:-}" ]; then
	a733_block "set A733_PCK600_CHECK_COMMAND for PCK600 and DSU/DDR devfreq"
fi
sh -c "$A733_PCK600_CHECK_COMMAND" >"$A733_TMPDIR/pck600.txt"
a733_add_check opp-transitions pass "both clusters and regulator voltages"
a733_add_check pck600-devfreq pass "PCK600, DSU and DDR"
a733_pass
