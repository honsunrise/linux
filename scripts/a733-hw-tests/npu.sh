#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin npu.sh
a733_require_command jq strace vpm_run python3

[ -c /dev/vipcore ] || a733_block "/dev/vipcore is unavailable"
model_dir=${A733_NPU_MODEL_DIR:-}
[ -n "$model_dir" ] || a733_block "set A733_NPU_MODEL_DIR"
work="$A733_TMPDIR/npu"
mkdir -p "$work"
python3 - "$work" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
for name,size in [('detector.input',98304),('landmarks.input',393216),('blendshapes.input',584)]:
    (root/name).write_bytes(bytes(size))
PY

default_profiles="detector:face_detector_nbg_int16/network_binary.nb:detector.input:0.67
landmarks:face_landmarks_detector_nbg_int16/network_binary.nb:landmarks.input:3.16
blendshapes:face_blendshapes_nbg_int16/network_binary.nb:blendshapes.input:0.48"
profiles=${A733_NPU_PROFILES:-$default_profiles}
metrics='{}'
for profile in $profiles; do
	name=${profile%%:*}
	rest=${profile#*:}; model=${rest%%:*}
	rest=${rest#*:}; input=${rest%%:*}; baseline=${rest##*:}
	[ -f "$model_dir/$model" ] || a733_block "missing NPU model $model"
	sample="$work/$name.sample.txt"
	printf '[network]\n%s\n[input]\n%s\n' \
		"$model_dir/$model" "$work/$input" >"$sample"
	strace -f -e openat,ioctl -o "$work/$name.strace" \
		vpm_run -s "$sample" -l 100 >"$work/$name.out" 2>&1
	grep -F '/dev/vipcore' "$work/$name.strace" >/dev/null || \
		a733_fail "$name did not use /dev/vipcore ioctl"
	time_ms=$(sed -n \
		's/.*[Pp]rofile[^0-9]*\([0-9][0-9.]*\)[[:space:]]*ms.*/\1/p' \
		"$work/$name.out" | tail -n1)
	[ -n "$time_ms" ] || a733_fail "cannot parse $name profile time"
	awk -v value="$time_ms" -v baseline="$baseline" \
		'BEGIN { exit !(value <= baseline * 2) }' || \
		a733_fail "$name profile time $time_ms ms exceeds twice baseline $baseline ms"
	metrics=$(printf '%s' "$metrics" |
		jq --arg key "$name" --argjson value "$time_ms" '.[$key]=$value')
done
a733_metric_json profile_ms "$metrics"
a733_add_check vipcore pass "hardware ioctl observed"
a733_add_check performance pass "all profiles <= 2x published baseline"
a733_pass
