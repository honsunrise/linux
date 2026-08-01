#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -eu
# shellcheck source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
a733_begin board-io-security.sh
a733_require_command jq rngtest journalctl

if [ -r /dev/hwrng ]; then
	timeout 60 rngtest -c 1000 </dev/hwrng \
		>"$A733_TMPDIR/rngtest.txt" 2>&1 || a733_fail "rngtest failed"
else
	a733_fail "/dev/hwrng is unavailable"
fi
if [ -r /proc/crypto ]; then
	grep -q '^selftest.*passed' /proc/crypto || \
		a733_fail "kernel crypto selftests do not report passed"
fi

commands="A733_MAILBOX_COMMAND A733_HWSPINLOCK_COMMAND
A733_FAN_COMMAND A733_LED_COMMAND A733_GPIO_COMMAND
A733_ADC_KEYS_COMMAND A733_IR_COMMAND A733_SPI_COMMAND
A733_I2C_SENSOR_COMMAND A733_BOARD_IO_SUSPEND_COMMAND"
for command_var in $commands; do
	value=$(printenv "$command_var" 2>/dev/null || true)
	[ -n "$value" ] || a733_block "set $command_var for the corresponding physical fixture"
	sh -c "$value" >"$A733_TMPDIR/$command_var.txt"
done
board_errors='hwspinlock.*timeout|mailbox.*error|crypto.*self-test failed'
board_errors="$board_errors|rng.*failure|gpio.*error|i2c.*timeout|spi.*error"
if journalctl -k --since "$A733_STARTED_AT" |
	grep -Ei "$board_errors" >"$A733_TMPDIR/kernel-errors.txt"; then
	a733_fail "board I/O or security errors appeared"
fi
a733_add_check crypto-rng pass "kernel selftests and rngtest"
a733_add_check mailbox-hwspinlock pass contention
a733_add_check cooling-led-gpio pass physical-fixtures
a733_add_check adc-keys-ir-spi-i2c pass physical-fixtures
a733_add_check suspend-resume pass board-io
a733_pass
