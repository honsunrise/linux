#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin audio.sh
a733_require_command jq aplay arecord ffmpeg ffprobe journalctl

vectors=${A733_TEST_VECTOR_DIR:-}
[ -n "$vectors" ] || a733_block "set A733_TEST_VECTOR_DIR"
tone="$vectors/a733-tone.wav"
[ -f "$tone" ] || a733_block "missing audio vector a733-tone.wav"
playback=${A733_AUDIO_PLAYBACK_DEVICE:-}
capture=${A733_AUDIO_CAPTURE_DEVICE:-}
hdmi=${A733_HDMI_AUDIO_DEVICE:-}
[ -n "$playback" ] || a733_block "set A733_AUDIO_PLAYBACK_DEVICE"
[ -n "$capture" ] || a733_block "set A733_AUDIO_CAPTURE_DEVICE"
[ -n "$hdmi" ] || a733_block "set A733_HDMI_AUDIO_DEVICE"
loopback="$A733_TMPDIR/loopback.wav"

aplay -D "$playback" "$tone" >"$A733_TMPDIR/playback.txt" 2>&1 &
play_pid=$!
arecord -D "$capture" -f S16_LE -r 48000 -c 2 -d 10 "$loopback" >"$A733_TMPDIR/capture.txt" 2>&1
wait "$play_pid"
probe=$(ffprobe -v error -show_entries stream=sample_rate,channels -of json "$loopback")
sample_rate=$(printf '%s' "$probe" | jq -r '.streams[0].sample_rate')
channels=$(printf '%s' "$probe" | jq -r '.streams[0].channels')
[ "$sample_rate" -eq 48000 ] || a733_fail "loopback is not 48 kHz"
[ "$channels" -eq 2 ] || a733_fail "loopback is not stereo"
analysis="$A733_TMPDIR/analysis.txt"
ffmpeg -v error -i "$loopback" -af astats=metadata=1:reset=0 -f null - 2>"$analysis"
if [ -z "${A733_AUDIO_ANALYSIS_COMMAND:-}" ]; then
	a733_block "set A733_AUDIO_ANALYSIS_COMMAND for frequency/RMS/THD+N"
fi
sh -c "$A733_AUDIO_ANALYSIS_COMMAND" >"$A733_TMPDIR/quality.json"
jq -e '
	.frequency_hz >= 999 and
	.frequency_hz <= 1001 and
	.rms_delta_db >= -3 and
	.rms_delta_db <= 3 and
	.thdn_delta_db <= 3
' "$A733_TMPDIR/quality.json" >/dev/null ||
	a733_fail "audio loopback quality is outside baseline tolerance"
aplay -D "$hdmi" "$tone" >"$A733_TMPDIR/hdmi.txt" 2>&1
if [ -n "${A733_AUDIO_SUSPEND_COMMAND:-}" ]; then
	sh -c "$A733_AUDIO_SUSPEND_COMMAND" >"$A733_TMPDIR/suspend.txt"
else
	a733_block "set A733_AUDIO_SUSPEND_COMMAND for suspend/resume"
fi
audio_errors='ALSA.*XRUN|xrun loop|sound card.*(lost|error)'
if journalctl -k --since "$A733_STARTED_AT" |
	grep -Ei "$audio_errors" >"$A733_TMPDIR/kernel-errors.txt"; then
	a733_fail "audio XRUN loop or card loss appeared"
fi
a733_metric_json quality "$(cat "$A733_TMPDIR/quality.json")"
a733_add_check analog-loopback pass "48 kHz stereo"
a733_add_check signal-quality pass "1 kHz/RMS/THD+N"
a733_add_check hdmi-audio pass "$hdmi"
a733_add_check suspend-resume pass audio
a733_pass
