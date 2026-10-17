#!/usr/bin/env bash
# Runs the headless test suite and fails on any SCRIPT ERROR in the log.
cd "$(dirname "$0")/.."
LOG=$(mktemp)
godot --headless --path . -s tests/test_headless.gd 2>&1 | tee "$LOG"
CODE=${PIPESTATUS[0]}
if grep -q "SCRIPT ERROR" "$LOG"; then echo "FAIL  SCRIPT ERROR found in log"; CODE=1; fi
rm -f "$LOG"
exit $CODE
