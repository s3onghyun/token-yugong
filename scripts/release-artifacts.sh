#!/bin/sh
# Produce the ad-hoc signed archive and its SHA-256 sidecar (local builds, and release runs without the
# signing secrets). Published releases are re-signed, notarized and stapled by scripts/notarize-app.sh.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
version=$(tr -d '\r\n' < "$root/VERSION")
dist="$root/dist"

rm -rf "$dist"
mkdir -p "$dist"
VERSION="$version" ARCHS=universal "$root/scripts/bundle.sh"
archive="$dist/TokenYugong-$version-macos-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$root/build/TokenYugong.app" "$archive"
(cd "$dist" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
printf '%s\n' "$archive"
