#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin gpu.sh
a733_require_command jq modinfo sha256sum journalctl

module_path=$(modinfo -n pvrsrvkm 2>/dev/null || true)
[ -n "$module_path" ] && [ -f "$module_path" ] || a733_block "pvrsrvkm is unavailable"
module_sha=$(sha256sum "$module_path" | cut -d' ' -f1)
render_node=${A733_GPU_RENDER_NODE:-/dev/dri/renderD128}
[ -c "$render_node" ] || a733_fail "render node is absent: $render_node"
pvr_run=${A733_PVR_RUN:-pvr-run}
command -v "$pvr_run" >/dev/null 2>&1 || a733_block "pvr-run wrapper is unavailable"

prime_test=${A733_GPU_PRIME_TEST:-}
[ -x "$prime_test" ] || a733_block "set executable A733_GPU_PRIME_TEST"
"$pvr_run" "$prime_test" "$render_node" >"$A733_TMPDIR/prime.txt"
"$pvr_run" vulkaninfo --summary >"$A733_TMPDIR/vulkan.txt"
grep -Ei 'PowerVR|IMG' "$A733_TMPDIR/vulkan.txt" >/dev/null || \
	a733_fail "vulkaninfo does not report PowerVR"

benchmark=${A733_GPU_BENCHMARK:-}
[ -x "$benchmark" ] || a733_block "set executable A733_GPU_BENCHMARK"
"$pvr_run" "$benchmark" >"$A733_TMPDIR/benchmark.txt"
if [ -n "${A733_GPU_LIFECYCLE_COMMAND:-}" ]; then
	sh -c "$A733_GPU_LIFECYCLE_COMMAND" >"$A733_TMPDIR/lifecycle.txt" 2>&1
else
	a733_block "set A733_GPU_LIFECYCLE_COMMAND for 100 compositor cycles"
fi
if [ -n "${A733_GPU_COMPOSITOR_COMMAND:-}" ]; then
	timeout 3600 sh -c "$A733_GPU_COMPOSITOR_COMMAND" \
		>"$A733_TMPDIR/compositor.txt" 2>&1
else
	a733_block "set A733_GPU_COMPOSITOR_COMMAND for one-hour compositor load"
fi
gpu_errors='pvrsrvkm.*(lockup|timeout|reset|leak)'
gpu_errors="$gpu_errors|mutex_spin_on_owner|hard LOCKUP"
if journalctl -k --since "$A733_STARTED_AT" |
	grep -Ei "$gpu_errors" >"$A733_TMPDIR/kernel-errors.txt"; then
	a733_fail "PowerVR lockup/reset/leak appeared in kernel log"
fi
a733_metric_string module_path "$module_path"
a733_metric_string module_sha256 "$module_sha"
a733_metric_string render_node "$render_node"
a733_add_check module pass "$module_sha"
a733_add_check prime-import pass "foreign dma-buf readback"
a733_add_check vulkan pass "PowerVR Vulkan device"
a733_add_check lifecycle pass "100 start/stop cycles"
a733_add_check compositor pass "3600 seconds"
a733_pass
