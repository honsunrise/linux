#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin gmac.sh
a733_require_command jq ip ethtool ping iperf3 journalctl

interface=${A733_GMAC_INTERFACE:-end0}
server=${A733_IPERF_SERVER:-192.168.50.51}
gateway=${A733_GATEWAY:-192.168.50.1}
link=$(ethtool "$interface")
phy_id=$(cat "/sys/class/net/$interface/phydev/phy_id")
address=$(ip -4 -j address show dev "$interface" |
	jq -r '.[0].addr_info[] | select(.scope == "global") |
		"\(.local)/\(.prefixlen)"' | sed -n '1p')

a733_metric_string interface "$interface"
a733_metric_string phy_id "$phy_id"
a733_metric_string address "$address"
a733_metric_string link "$link"

printf '%s\n' "$link" | grep -F 'Speed: 1000Mb/s' >/dev/null || a733_fail "link is not 1000 Mb/s"
printf '%s\n' "$link" | grep -F 'Duplex: Full' >/dev/null || a733_fail "link is not full duplex"
case "${phy_id#0x}" in
	7b744412 | 7b744412*) ;;
	*) a733_fail "unexpected PHY ID: $phy_id" ;;
esac

forward="$A733_TMPDIR/forward.json"
reverse="$A733_TMPDIR/reverse.json"
iperf3 -c "$server" -P 4 -t 60 -J >"$forward"
iperf3 -c "$server" -P 4 -t 60 -R -J >"$reverse"
forward_bps=$(jq -r '.end.sum_received.bits_per_second' "$forward")
reverse_bps=$(jq -r '.end.sum_received.bits_per_second' "$reverse")
for value in "$forward_bps" "$reverse_bps"; do
	awk -v value="$value" 'BEGIN { exit !(value >= 800000000) }' || \
		a733_fail "iperf aggregate below 800 Mbit/s: $value"
done
ping -c 100 "$gateway" >"$A733_TMPDIR/ping.txt"
gmac_errors='stmmac.*(error|timeout)|Link is Down|eth_lpi.*lost'
if journalctl -k --since "$A733_STARTED_AT" |
	grep -Ei "$gmac_errors" >"$A733_TMPDIR/kernel-errors.txt"; then
	a733_fail "GMAC errors appeared in the kernel log"
fi
a733_metric_json forward_bits_per_second "$forward_bps"
a733_metric_json reverse_bits_per_second "$reverse_bps"
a733_add_check link pass "1000/full PHY $phy_id"
a733_add_check throughput pass "forward=$forward_bps reverse=$reverse_bps"
a733_add_check packet-loss pass "100 gateway pings"
if [ -z "${A733_GMAC_LINK_CYCLE_COMMAND:-}" ]; then
	a733_block "set A733_GMAC_LINK_CYCLE_COMMAND for ten physical link cycles"
fi
sh -c "$A733_GMAC_LINK_CYCLE_COMMAND" >"$A733_TMPDIR/link-cycles.txt"
boot_evidence=${A733_GMAC_REBOOT_EVIDENCE:-}
if [ -z "$boot_evidence" ] || [ ! -f "$boot_evidence" ]; then
	a733_block "provide A733_GMAC_REBOOT_EVIDENCE for three reboot checks"
fi
jq -e '.reboots >= 3 and .link_losses == 0' "$boot_evidence" >/dev/null || \
	a733_fail "GMAC reboot evidence failed"
a733_add_check link-cycles pass "ten cycles"
a733_add_check reboot-soak pass "three reboots"
a733_pass
