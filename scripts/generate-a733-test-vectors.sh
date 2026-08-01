#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

output_dir=${1:?usage: generate-a733-test-vectors.sh OUTPUT_DIR}
ffmpeg=${FFMPEG:-ffmpeg}
ffprobe=${FFPROBE:-ffprobe}
nixpkgs_rev=${NIXPKGS_REV:?set NIXPKGS_REV to the locked nixpkgs revision}
for command_name in "$ffmpeg" "$ffprobe" jq sha256sum stat; do
	command -v "$command_name" >/dev/null 2>&1 || {
		echo "missing command: $command_name" >&2
		exit 1
	}
done
mkdir -p "$output_dir"
if [ -n "$(find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
	echo "output directory is not empty: $output_dir" >&2
	exit 1
fi

raw="$output_dir/a733-1080p30.yuv"
h264="$output_dir/a733-1080p30.h264"
h265="$output_dir/a733-1080p30.h265"
h264_golden="$output_dir/a733-1080p30-h264-golden.yuv"
h265_golden="$output_dir/a733-1080p30-h265-golden.yuv"
tone="$output_dir/a733-tone.wav"

"$ffmpeg" -hide_banner -loglevel error \
	-f lavfi -i testsrc2=size=1920x1080:rate=30 -t 10 \
	-pix_fmt yuv420p -f rawvideo "$raw"
"$ffmpeg" -hide_banner -loglevel error \
	-f rawvideo -pixel_format yuv420p -video_size 1920x1080 -framerate 30 \
	-i "$raw" -frames:v 300 -c:v libx264 -preset medium -crf 23 \
	-x264-params threads=1:sync-lookahead=0 -f h264 "$h264"
"$ffmpeg" -hide_banner -loglevel error \
	-f rawvideo -pixel_format yuv420p -video_size 1920x1080 -framerate 30 \
	-i "$raw" -frames:v 300 -c:v libx265 -preset medium \
	-x265-params pools=1:frame-threads=1:wpp=0:crf=28 -f hevc "$h265"
"$ffmpeg" -hide_banner -loglevel error -i "$h264" -frames:v 300 \
	-pix_fmt yuv420p -f rawvideo "$h264_golden"
"$ffmpeg" -hide_banner -loglevel error -i "$h265" -frames:v 300 \
	-pix_fmt yuv420p -f rawvideo "$h265_golden"
"$ffmpeg" -hide_banner -loglevel error \
	-f lavfi -i 'sine=frequency=1000:sample_rate=48000:duration=10' \
	-ac 2 -c:a pcm_s16le "$tone"

for bitstream in "$h264" "$h265"; do
	frames=$("$ffprobe" -v error -count_frames -select_streams v:0 \
		-show_entries stream=nb_read_frames -of csv=p=0 "$bitstream")
	[ "$frames" -eq 300 ] || {
		echo "$bitstream decoded to $frames frames" >&2
		exit 1
	}
done
expected_raw_size=$((1920 * 1080 * 3 * 300 / 2))
[ "$(stat -c %s "$raw")" -eq "$expected_raw_size" ]
[ "$(stat -c %s "$h264_golden")" -eq "$expected_raw_size" ]
[ "$(stat -c %s "$h265_golden")" -eq "$expected_raw_size" ]

metadata="$output_dir/a733-test-vectors.lock.generated"
file_json() {
	path=$1
	format=$2
	command_line=$3
	jq -cn \
		--arg command "$command_line" \
		--arg sha256 "$(sha256sum "$path" | cut -d' ' -f1)" \
		--argjson size "$(stat -c %s "$path")" \
		--arg format "$format" \
		'{command:$command,sha256:$sha256,size:$size,format:$format,runtime_seconds:10}'
}
raw_command='ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=30 -t 10'
raw_command+=' -pix_fmt yuv420p -f rawvideo a733-1080p30.yuv'
h264_command='ffmpeg -f rawvideo -pixel_format yuv420p -video_size 1920x1080'
h264_command+=' -framerate 30 -i a733-1080p30.yuv -frames:v 300'
h264_command+=' -c:v libx264 -preset medium -crf 23'
h264_command+=' -x264-params threads=1:sync-lookahead=0 -f h264 a733-1080p30.h264'
h265_command='ffmpeg -f rawvideo -pixel_format yuv420p -video_size 1920x1080'
h265_command+=' -framerate 30 -i a733-1080p30.yuv -frames:v 300'
h265_command+=' -c:v libx265 -preset medium'
h265_command+=' -x265-params pools=1:frame-threads=1:wpp=0:crf=28'
h265_command+=' -f hevc a733-1080p30.h265'
h264_golden_command='ffmpeg -i a733-1080p30.h264 -frames:v 300 -pix_fmt yuv420p'
h264_golden_command+=' -f rawvideo a733-1080p30-h264-golden.yuv'
h265_golden_command='ffmpeg -i a733-1080p30.h265 -frames:v 300 -pix_fmt yuv420p'
h265_golden_command+=' -f rawvideo a733-1080p30-h265-golden.yuv'
tone_command='ffmpeg -f lavfi -i sine=frequency=1000:sample_rate=48000:duration=10'
tone_command+=' -ac 2 -c:a pcm_s16le a733-tone.wav'

raw_json=$(file_json "$raw" \
	'rawvideo:yuv420p:1920x1080:30fps:300frames' "$raw_command")
h264_json=$(file_json "$h264" 'h264-annex-b:300frames' "$h264_command")
h265_json=$(file_json "$h265" 'hevc-annex-b:300frames' "$h265_command")
h264_golden_json=$(file_json "$h264_golden" \
	'rawvideo:yuv420p:1920x1080:300frames' "$h264_golden_command")
h265_golden_json=$(file_json "$h265_golden" \
	'rawvideo:yuv420p:1920x1080:300frames' "$h265_golden_command")
tone_json=$(file_json "$tone" \
	'wav:pcm_s16le:48000Hz:stereo:1000Hz' "$tone_command")

fio_command='fio --name=a733-ufs-test --filename=/persistent/.a733-ufs-test'
fio_command+=' --size=1G --rw=randrw --rwmixread=70 --bs=128k --iodepth=16'
fio_command+=' --direct=1 --fsync=32 --runtime=300 --time_based'
fio_command+=' --verify=crc32c --do_verify=1'
gpu_source='ayiejosh/a733-powervr-fex@'
gpu_source+='28c82689457033ac658fe863f230d8abf4e5b7c4'
npu_model_source='arnaudlvq/MediaPipe-FaceLandmarker-NPU-Version-'
npu_model_source+='A733-VeriSilicon-VIP9000@'
npu_model_source+='925773701b5bb07515d976ee31fd4468d6ecb373'
npu_runtime_source='ZIFENG278/ai-sdk@'
npu_runtime_source+='fc90006d0f6569da2f6726c2d8395877686f5aca'
lock_filter=$(cat <<'JQ'
{
  schema_version: $schema_version,
  tool: {
    path: $ffmpeg_path,
    version: $ffmpeg_version,
    nixpkgs_rev: $nixpkgs_rev
  },
  fixtures: {
    "a733-1080p30.yuv": $raw,
    "a733-1080p30.h264": $h264,
    "a733-1080p30.h265": $h265,
    "a733-1080p30-h264-golden.yuv": $h264_golden,
    "a733-1080p30-h265-golden.yuv": $h265_golden,
    "a733-tone.wav": $tone
  },
  fio: {
    ufs: $fio_command,
    pcie: "same job with an independent 1 GiB regular file on A733_PCIE_TEST_MOUNT"
  },
  archives: {
    gpu_prime: {source: $gpu_source, sha256: $gpu_hash},
    npu_models: {source: $npu_model_source, sha256: $npu_model_hash},
    npu_runtime: {source: $npu_runtime_source, sha256: $npu_runtime_hash}
  },
  thresholds: {
    decoder_frames: 300,
    encoder_runs: 2,
    encoder_frames_per_run: 300,
    encoder_psnr_delta_db: -0.5,
    encoder_ssim_delta: -0.005,
    audio_frequency_hz_tolerance: 1,
    audio_rms_delta_db: 3,
    audio_thdn_delta_db: 3,
    npu_max_published_baseline_multiple: 2
  },
  output_schema: {
    schema_version: 1,
    required: [
      "test_id", "status", "candidate_id", "kernelrelease",
      "started_at", "finished_at", "reason", "checks", "metrics"
    ],
    status: ["pass", "blocked", "fail", "not-applicable"]
  }
}
JQ
)

jq -n \
	--argjson schema_version 1 \
	--arg ffmpeg_path "$(command -v "$ffmpeg")" \
	--arg ffmpeg_version "$("$ffmpeg" -version | sed -n '1p')" \
	--arg nixpkgs_rev "$nixpkgs_rev" \
	--argjson raw "$raw_json" \
	--argjson h264 "$h264_json" \
	--argjson h265 "$h265_json" \
	--argjson h264_golden "$h264_golden_json" \
	--argjson h265_golden "$h265_golden_json" \
	--argjson tone "$tone_json" \
	--arg fio_command "$fio_command" \
	--arg gpu_source "$gpu_source" \
	--arg gpu_hash 0c25fd5dd483d8d3fb9dd2df33ffc0656929c568c5aabc3afb9cf2d5fab4f546 \
	--arg npu_model_source "$npu_model_source" \
	--arg npu_model_hash 108ed69343d6161988daf9426e931e3189bbc25ffd940d8204f98c9458dc0e1c \
	--arg npu_runtime_source "$npu_runtime_source" \
	--arg npu_runtime_hash c562e7ed8a5a6f341029e521bdf05568f7ba25e26c5da426eb3d9d45db171cae \
	"$lock_filter" >"$metadata"
chmod 0444 "$metadata"
