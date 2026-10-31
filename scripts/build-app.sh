#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/swift.sh build -c release
app="$PWD/build/Kadrin.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Screenshot "$app/Contents/MacOS/Screenshot"
iconset="$PWD/build/Kadrin.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" assets/branding/frames-icon-v6.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" assets/branding/frames-icon-v6.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Screenshot</string>
<key>CFBundleIdentifier</key><string>com.saidazam.screenshot</string>
<key>CFBundleName</key><string>Kadrin</string>
<key>CFBundleDisplayName</key><string>Kadrin</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - --identifier com.saidazam.screenshot "$app"
printf '%s\n' "$app"
