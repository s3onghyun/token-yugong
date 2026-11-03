#!/bin/sh
# Builds build/YugongPet.app: release binary, pixel app icon, the status-line bridge, ad-hoc signature.
# Not notarized. Nothing is installed; move the app wherever you like (e.g. /Applications).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
version=${VERSION:-$(tr -d '\r\n' < "$root/VERSION")}
bundle_identifier=${TOKENPET_BUNDLE_IDENTIFIER:-dev.yugongpet.app}
app="$root/build/YugongPet.app"

# SwiftPM does not make a universal executable in one invocation. Build both macOS
# architectures in separate scratch directories, then combine them with lipo.
case ${ARCHS:-universal} in
  universal) architectures="arm64 x86_64" ;;
  arm64|x86_64) architectures=${ARCHS} ;;
  *) echo "ARCHS must be universal, arm64, or x86_64" >&2; exit 2 ;;
esac

bins=""
for architecture in $architectures; do
  scratch="$root/.build/$architecture-release"
  swift build --package-path "$root" --scratch-path "$scratch" -c release \
    --triple "$architecture-apple-macosx13.0" --product TokenPet
  bins="$bins $(swift build --package-path "$root" --scratch-path "$scratch" -c release \
    --triple "$architecture-apple-macosx13.0" --show-bin-path)/TokenPet"
done

set -- $bins
if [ "$#" -eq 1 ]; then
  bin=$1
else
  bin="$root/build/TokenPet-universal"
  lipo -create "$@" -output "$bin"
fi

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
  <key>CFBundleIdentifier</key><string>$bundle_identifier</string>
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
