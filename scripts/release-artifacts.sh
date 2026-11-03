#!/bin/sh
# Produce the notarization-free release archive and its SHA-256 sidecar.
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
