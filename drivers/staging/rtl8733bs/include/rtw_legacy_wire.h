/* SPDX-License-Identifier: GPL-2.0 */
/*
 * On-wire layouts for the legacy protocols that NAT25 still has to parse
 * while bridging frames.  The IPX and AppleTalk stacks and their headers
 * were removed from Linux, but the byte layouts are unchanged and the
 * driver only inspects them.
 */
#ifndef _RTW_LEGACY_WIRE_H_
#define _RTW_LEGACY_WIRE_H_

#include <linux/types.h>
#include <linux/if_ether.h>

struct rtw_ipx_address {
	__be32 net;
	u8 node[6];
	__be16 sock;
} __packed;

struct rtw_ipxhdr {
	__be16 ipx_checksum;
	__be16 ipx_pktsize;
	u8 ipx_tctrl;
	u8 ipx_type;
	struct rtw_ipx_address ipx_dest;
	struct rtw_ipx_address ipx_source;
} __packed;

struct rtw_ddpehdr {
	__be16 deh_len_hops;
	__be16 deh_sum;
	__be16 deh_dnet;
	__be16 deh_snet;
	u8 deh_dnode;
	u8 deh_snode;
	u8 deh_dport;
	u8 deh_sport;
} __packed;

struct rtw_elapaarp {
	__be16 hw_type;
#define AARP_HW_TYPE_ETHERNET	1
#define AARP_HW_TYPE_TOKENRING	2
	__be16 pa_type;
	u8 hw_len;
	u8 pa_len;
#define AARP_PA_ALEN		4
	__be16 function;
#define AARP_REQUEST		1
#define AARP_REPLY			2
#define AARP_PROBE			3
	u8 hw_src[ETH_ALEN];
	u8 pa_src_zero;
	__be16 pa_src_net;
	u8 pa_src_node;
	u8 hw_dst[ETH_ALEN];
	u8 pa_dst_zero;
	__be16 pa_dst_net;
	u8 pa_dst_node;
} __packed;

#endif /* _RTW_LEGACY_WIRE_H_ */
