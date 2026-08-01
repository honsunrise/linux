#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin gnss.sh
vendor_dts=${A733_VENDOR_REFERENCE_DTS:?set A733_VENDOR_REFERENCE_DTS}
[ -f "$vendor_dts" ] || a733_fail "vendor reference DTS is absent"
if grep -Ei 'gnss|gps' "$vendor_dts" >"$A733_TMPDIR/matches.txt"; then
	a733_fail "official A7A DTS unexpectedly contains a GNSS/GPS node"
fi
a733_add_check official-dts pass "no GNSS node"
a733_not_applicable "official A7A DTS has no GNSS hardware node"
