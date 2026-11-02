#!/bin/sh
# Builds build/YugongPet.app: release binary, pixel app icon, the status-line bridge, ad-hoc signature.
# Not notarized. Nothing is installed; move the app wherever you like (e.g. /Applications).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
version=0.1.0
app="$root/build/YugongPet.app"

swift build --package-path "$root" -c release --product TokenPet
bin="$(swift build --package-path "$root" -c release --show-bin-path)/TokenPet"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/TokenPet"
cp "$root/bridge/statusline-bridge.sh" "$app/Contents/Resources/"

iconset="$root/build/AppIcon.iconset"
rm -rf "$iconset"
"$bin" --icon-set "$iconset" >/dev/null
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$iconset"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.yugongpet.app</string>
  <key>CFBundleName</key><string>Yugong Pet</string>
  <key>CFBundleDisplayName</key><string>Yugong Pet</string>
  <key>CFBundleExecutable</key><string>TokenPet</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Code MIT; character art all rights reserved (see assets/LICENSE.md)</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$app"
echo "$app"
