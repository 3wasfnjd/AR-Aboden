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
# the loading page: the game's poster (tools/web/splash.png) fills the screen while the
# engine and the game data download (CSS in the preset's html/head_include)
cp tools/web/splash.png "$OUT/index.png"
# the browser tab and the home-screen name: the game's web title (the APK keeps its own)
sed -i 's|<title>[^<]*</title>|<title>BATTLESHIP · البارجة الحربية</title>|' "$OUT/index.html"
ls -la "$OUT"
