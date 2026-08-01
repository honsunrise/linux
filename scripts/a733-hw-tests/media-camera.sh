#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin media-camera.sh
a733_require_command jq ffmpeg ffprobe media-ctl v4l2-ctl sha256sum

vectors=${A733_TEST_VECTOR_DIR:-}
[ -n "$vectors" ] || a733_block "set A733_TEST_VECTOR_DIR"
for file in a733-1080p30.yuv a733-1080p30-h264-golden.yuv a733-1080p30-h265-golden.yuv; do
	[ -f "$vectors/$file" ] || a733_block "missing media vector $file"
done
media-ctl -p >"$A733_TMPDIR/media-graph.txt"
v4l2-ctl --list-devices >"$A733_TMPDIR/v4l2-devices.txt"

[ -n "${A733_HW_H264_DECODE_COMMAND:-}" ] || a733_block "set A733_HW_H264_DECODE_COMMAND"
[ -n "${A733_HW_H265_DECODE_COMMAND:-}" ] || a733_block "set A733_HW_H265_DECODE_COMMAND"
A733_MEDIA_INPUT="$vectors/a733-1080p30.h264" \
	A733_MEDIA_OUTPUT="$A733_TMPDIR/h264.yuv" \
	sh -c "$A733_HW_H264_DECODE_COMMAND"
A733_MEDIA_INPUT="$vectors/a733-1080p30.h265" \
	A733_MEDIA_OUTPUT="$A733_TMPDIR/h265.yuv" \
	sh -c "$A733_HW_H265_DECODE_COMMAND"
for codec in h264 h265; do
	output="$A733_TMPDIR/$codec.yuv"
	golden="$vectors/a733-1080p30-$codec-golden.yuv"
	[ -f "$output" ] || a733_fail "$codec hardware decoder produced no output"
	[ "$(sha256sum "$output" | cut -d' ' -f1)" = "$(sha256sum "$golden" | cut -d' ' -f1)" ] || \
		a733_fail "$codec decoder output differs from software golden"
done

[ -n "${A733_HW_ENCODE_COMMAND:-}" ] || a733_block "set A733_HW_ENCODE_COMMAND"
for run in 1 2; do
	A733_MEDIA_INPUT="$vectors/a733-1080p30.yuv" \
		A733_MEDIA_OUTPUT="$A733_TMPDIR/encode-$run.bin" \
		sh -c "$A733_HW_ENCODE_COMMAND"
	ffmpeg -v error -i "$A733_TMPDIR/encode-$run.bin" -frames:v 300 \
		-pix_fmt yuv420p -f rawvideo "$A733_TMPDIR/encode-$run.yuv"
	frames=$(ffprobe -v error -count_frames -select_streams v:0 \
		-show_entries stream=nb_read_frames -of csv=p=0 \
		"$A733_TMPDIR/encode-$run.bin")
	[ "$frames" -eq 300 ] || a733_fail "encoder run $run produced $frames frames"
done
encode_1_hash=$(sha256sum "$A733_TMPDIR/encode-1.yuv" | cut -d' ' -f1)
encode_2_hash=$(sha256sum "$A733_TMPDIR/encode-2.yuv" | cut -d' ' -f1)
[ "$encode_1_hash" = "$encode_2_hash" ] || \
	a733_fail "normalized encoder outputs are not deterministic"

if [ -n "${A733_MEDIA_QUALITY_COMMAND:-}" ]; then
	sh -c "$A733_MEDIA_QUALITY_COMMAND" >"$A733_TMPDIR/quality.json"
	jq -e '.psnr >= (.vendor_psnr - 0.5) and
		.ssim >= (.vendor_ssim - 0.005)' \
		"$A733_TMPDIR/quality.json" >/dev/null || \
		a733_fail "encoder PSNR/SSIM is below baseline threshold"
else
	a733_block "set A733_MEDIA_QUALITY_COMMAND for PSNR/SSIM analysis"
fi
for command_var in A733_G2D_COMMAND A733_DI_COMMAND A733_CAMERA_COMMAND; do
	value=$(printenv "$command_var" 2>/dev/null || true)
	[ -n "$value" ] || a733_block "set $command_var"
	sh -c "$value" >"$A733_TMPDIR/$command_var.txt"
done
a733_add_check decoder pass "H.264/H.265 golden hashes"
a733_add_check encoder pass "two deterministic 300-frame runs"
a733_add_check quality pass "PSNR/SSIM thresholds"
a733_add_check camera-g2d-di pass "hardware fixture commands"
a733_pass
