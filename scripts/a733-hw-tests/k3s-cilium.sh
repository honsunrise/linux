#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin k3s-cilium.sh
a733_require_command jq systemctl k3s tee bpftool ip

systemctl is-active --quiet k3s || a733_fail "k3s is not active"
node_json="$A733_TMPDIR/node.json"
if ! sudo k3s kubectl get node seldon-1 -o json |
	tee "$node_json" >/dev/null; then
	a733_fail "Kubernetes API cannot read seldon-1"
fi
ready=$(jq -r '.status.conditions[]|select(.type=="Ready")|.status' "$node_json")
kernel=$(jq -r '.status.nodeInfo.kernelVersion' "$node_json")
[ "$ready" = True ] || a733_fail "seldon-1 is not Ready"
[ "$kernel" = "$(uname -r)" ] || a733_fail "Kubernetes reports stale kernel $kernel"
if ! sudo k3s kubectl get pods -A -l k8s-app=cilium -o json |
	tee "$A733_TMPDIR/cilium-pods.json" >/dev/null; then
	a733_fail "Kubernetes API cannot list Cilium pods"
fi
not_ready=$(jq '
	[.items[] | select(any(.status.containerStatuses[]?; .ready != true))] |
	length
' "$A733_TMPDIR/cilium-pods.json")
[ "$not_ready" -eq 0 ] || a733_fail "$not_ready Cilium pods are not Ready"
if command -v cilium-dbg >/dev/null 2>&1; then
	cilium-dbg status --verbose --output json >"$A733_TMPDIR/cilium-status.json"
elif [ -n "${A733_CILIUM_STATUS_COMMAND:-}" ]; then
	sh -c "$A733_CILIUM_STATUS_COMMAND" >"$A733_TMPDIR/cilium-status.json"
else
	a733_block "install cilium-dbg or set A733_CILIUM_STATUS_COMMAND"
fi
jq -e '.cilium.state == "Ok" and .kubernetes.state == "Ok"' \
	"$A733_TMPDIR/cilium-status.json" >/dev/null || \
	a733_fail "Cilium status is not healthy"
if ! sudo k3s kubectl get --raw='/readyz?verbose' |
	tee "$A733_TMPDIR/readyz.txt" >/dev/null; then
	a733_fail "Kubernetes readyz endpoint is unavailable"
fi
if grep -vE '^\[\+\]|^ok$|^$' "$A733_TMPDIR/readyz.txt" >/dev/null; then
	a733_fail "Kubernetes readyz contains a failed check"
fi
if ! sudo bpftool map show | grep -q .; then
	a733_fail "BPF map inventory is empty"
fi
if ! ip -d link show type vxlan | grep -q .; then
	a733_fail "VXLAN link is absent"
fi
if [ -n "${A733_K3S_CONNECTIVITY_COMMAND:-}" ]; then
	sh -c "$A733_K3S_CONNECTIVITY_COMMAND" >"$A733_TMPDIR/connectivity.txt"
else
	a733_block "set A733_K3S_CONNECTIVITY_COMMAND for cross-node pod/service traffic"
fi
a733_metric_string kubernetes_kernel "$kernel"
a733_metric_json cilium_pod_count "$(jq '.items|length' "$A733_TMPDIR/cilium-pods.json")"
a733_add_check k3s pass active
a733_add_check cilium pass healthy
a733_add_check apiserver pass ready
a733_add_check cross-node-traffic pass "custom connectivity command"
a733_pass
