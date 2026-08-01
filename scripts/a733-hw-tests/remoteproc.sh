#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin remoteproc.sh
vendor_dts=${A733_VENDOR_REFERENCE_DTS:?set A733_VENDOR_REFERENCE_DTS}
[ -f "$vendor_dts" ] || a733_fail "vendor reference DTS is absent"
python3 - "$vendor_dts" <<'PY' >"$A733_TMPDIR/result.txt"
import re,sys
text=open(sys.argv[1],encoding='utf-8').read()
match=re.search(r'a55_rproc@0\s*\{(?P<body>.*?)\n\s*\};',text,re.S)
if not match:
    raise SystemExit('a55_rproc@0 is absent')
if not re.search(r'status\s*=\s*"disabled"\s*;',match.group('body')):
    raise SystemExit('a55_rproc@0 is not disabled')
print('a55_rproc@0 status=disabled')
PY
a733_add_check official-dts pass "$(cat "$A733_TMPDIR/result.txt")"
a733_not_applicable "official A7A DTS disables the A55 remoteproc node"
