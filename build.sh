#!/bin/bash
# Compila o SlapMac.app (universal: Apple Silicon + Intel) em ./build
set -euo pipefail
cd "$(dirname "$0")"

APP="build/SlapMac.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

echo "→ Compilando…"
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$ARCH-apple-macos13.0" \
    -parse-as-library Sources/*.swift -o "build/obj/SlapMac-$ARCH"
done
lipo -create build/obj/SlapMac-arm64 build/obj/SlapMac-x86_64 -output "$APP/Contents/MacOS/SlapMac"

cp Resources/*.mp3 "$APP/Contents/Resources/"

echo "→ Gerando ícone…"
swiftc -O Tools/make_icon.swift -o build/obj/make_icon
build/obj/make_icon build/obj/icon.png
ICONSET=build/obj/AppIcon.iconset && mkdir -p "$ICONSET"
for SZ in 16 32 128 256 512; do
  sips -z $SZ $SZ build/obj/icon.png --out "$ICONSET/icon_${SZ}x${SZ}.png" >/dev/null
  sips -z $((SZ*2)) $((SZ*2)) build/obj/icon.png --out "$ICONSET/icon_${SZ}x${SZ}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SlapMac</string>
  <key>CFBundleDisplayName</key><string>SlapMac</string>
  <key>CFBundleIdentifier</key><string>com.rafaelferreira.slapmac</string>
  <key>CFBundleExecutable</key><string>SlapMac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
  <key>NSMicrophoneUsageDescription</key><string>O SlapMac usa o microfone para ouvir tapas quando o Mac não tem acelerômetro.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "→ Assinando (ad-hoc)…"
codesign --force --deep --sign - "$APP"
echo "✓ Pronto: $APP"
