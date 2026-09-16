#!/bin/bash
# xterm.js vendor dosyalarını indirir ve VENDOR.md'deki sha256'larla karşılaştırır.
# Kullanım: ./update.sh   (bu dizinden)
set -euo pipefail
cd "$(dirname "$0")"

XTERM=6.0.0
FIT=0.11.0
SEARCH=0.16.0
WEBGL=0.19.0

base=https://cdn.jsdelivr.net/npm
curl -fsSL -o xterm.js        "$base/@xterm/xterm@$XTERM/lib/xterm.js"
curl -fsSL -o xterm.css       "$base/@xterm/xterm@$XTERM/css/xterm.css"
curl -fsSL -o addon-fit.js    "$base/@xterm/addon-fit@$FIT/lib/addon-fit.js"
curl -fsSL -o addon-search.js "$base/@xterm/addon-search@$SEARCH/lib/addon-search.js"
curl -fsSL -o addon-webgl.js  "$base/@xterm/addon-webgl@$WEBGL/lib/addon-webgl.js"
curl -fsSL -o LICENSE         "$base/@xterm/xterm@$XTERM/LICENSE"

echo "--- sha256 (VENDOR.md ile karşılaştır) ---"
shasum -a 256 xterm.js xterm.css addon-fit.js addon-search.js addon-webgl.js
