#!/bin/bash
# Reeve.app üretir.  Kullanım: Scripts/bundle.sh [debug|release]
#
# Neden gerekiyor: WKWebView'i çıplak SwiftPM binary'sinden çalıştırmak
# sürprizli (Info.plist yok, aktivasyon/odak davranışı eksik). Faz 0 dahil
# her görsel doğrulama .app üzerinden yapılır.
set -euo pipefail
cd "$(dirname "$0")/.."

CONF="${1:-release}"
swift build -c "$CONF"
BIN="$(swift build -c "$CONF" --show-bin-path)"
APP="build/Reeve.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Reeve" "$APP/Contents/MacOS/Reeve"

# Kaynaklar doğrudan Contents/Resources'a giriyor; Res.root önce orayı bakıyor.
# (SwiftPM'in Bundle.module'ü bundle'ı Reeve.app'in YANINDA arardı — Contents/ dışı.)
cp -R "$BIN/Reeve_Reeve.bundle/Resources/." "$APP/Contents/Resources/"
rm -f "$APP/Contents/Resources/vendor/update.sh" "$APP/Contents/Resources/vendor/VENDOR.md"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Reeve</string>
  <key>CFBundleIdentifier</key><string>io.reeve.app</string>
  <key>CFBundleName</key><string>Reeve</string>
  <key>CFBundleDisplayName</key><string>Reeve</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

# İmza. Gerçek bir kimlik varsa onu kullan, yoksa ad-hoc'a düş.
#
# Fark önemli: macOS, UNUserNotificationCenter'ı yalnızca gerçek imza kimliği olan
# uygulamalara açıyor. Ad-hoc imzada `requestAuthorization` doğrudan
# "Notifications are not allowed for this application" diyor — Dock rozeti çalışır,
# banner çalışmaz. Kimlik eklemek için: Xcode → Settings → Accounts → Apple ID
# (ücretsiz hesap yeter, "Apple Development" sertifikası üretir). Kod değişmiyor.
# `|| true` şart: set -e altında grep eşleşme bulamayınca (hiç kimlik yoksa)
# komut ikamesi hata döndürüyor ve script imza adımına hiç gelmiyordu.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
           | grep -oE '"Apple Development: [^"]+"' | head -1 | tr -d '"' || true)
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP" >/dev/null 2>&1 \
    && echo "imzalandı: $IDENTITY"
else
  codesign --force --sign - "$APP" >/dev/null 2>&1
  echo "ad-hoc imza — macOS bildirimleri kapalı, Dock rozeti çalışır"
fi

echo "$APP hazır"
