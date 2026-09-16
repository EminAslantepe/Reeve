#!/bin/bash
# Reeve.icns üretir.  Kullanım: Design/build-icon.sh
#
# Zincir: icon.swift → 1024 px PNG → on boyutluk .iconset → .icns
# Ara ürünler takip edilmiyor; tek kaynak icon.swift.
set -euo pipefail
cd "$(dirname "$0")"

swiftc -O icon.swift -o .icon-render
./.icon-render 1024
rm -f .icon-render

rm -rf Reeve.iconset && mkdir -p Reeve.iconset
while read -r px name; do
  sips -Z "$px" icon-1024.png --out "Reeve.iconset/$name.png" >/dev/null
done <<'SIZES'
16 icon_16x16
32 icon_16x16@2x
32 icon_32x32
64 icon_32x32@2x
128 icon_128x128
256 icon_128x128@2x
256 icon_256x256
512 icon_256x256@2x
512 icon_512x512
1024 icon_512x512@2x
SIZES

iconutil -c icns Reeve.iconset -o Reeve.icns
echo "Reeve.icns hazır ($(du -h Reeve.icns | cut -f1))"
