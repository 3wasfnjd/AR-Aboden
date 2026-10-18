#!/usr/bin/env bash
# Runs the headless test suite and fails on any SCRIPT ERROR in the log.
# GODOT=/path/to/godot overrides the binary (CI). --xr-mode off: OpenXR is enabled in
# project.godot for the Quest build; desktop and headless runs never start it.
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
LOG=$(mktemp)
# first run / fresh checkout: import resources (fonts, addons) before the tests
if [ ! -d .godot/imported ]; then
  "$GODOT" --headless --xr-mode off --path . --import >/dev/null 2>&1 || true
fi
"$GODOT" --headless --xr-mode off --path . -s tests/test_headless.gd 2>&1 | grep -v "OpenXR-Loader" | tee "$LOG"
CODE=${PIPESTATUS[0]}
if grep -q "SCRIPT ERROR" "$LOG"; then echo "FAIL  SCRIPT ERROR found in log"; CODE=1; fi
if ! grep -q "^RESULT OK" "$LOG"; then echo "FAIL  no 'RESULT OK' line"; CODE=1; fi
rm -f "$LOG"
exit $CODE
