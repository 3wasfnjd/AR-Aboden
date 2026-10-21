#!/usr/bin/env bash
# Exports the web free-play build (preset "Web") into ../table-war-web/ (served with the
# rest of the repository's web pages). GODOT=/path/to/godot overrides the binary.
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT=../table-war-web
mkdir -p "$OUT"
rm -f "$OUT"/index.*
"$GODOT" --headless --xr-mode off --path . --export-release "Web" "$OUT/index.html"
rm -f "$OUT"/index.pck-*
ls -la "$OUT"
