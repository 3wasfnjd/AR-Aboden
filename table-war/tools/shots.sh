#!/usr/bin/env bash
# Render the screenshot set into shots/.  Usage: tools/shots.sh [--only=<letters>]
cd "$(dirname "$0")/.."
xvfb-run -a -s "-screen 0 2600x1500x24" "${GODOT:-godot}" --xr-mode off --rendering-driver opengl3 --path . main.tscn -- --shots "$@" 2>&1 | grep -E -A3 "SHOT|STATS|IMPACT|SCRIPT ERROR"
