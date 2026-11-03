#!/bin/sh
# Runs the unit tests. With only the Command Line Tools installed, swift-testing lives in a
# framework folder SwiftPM does not search by default, without the Testing+Foundation overlay.
# CI sets DEVELOPER_DIR to a full Xcode so its compiler and Testing.framework always match.
developer_dir=${DEVELOPER_DIR:-$(xcode-select -p)}
F="$developer_dir/Library/Developer/Frameworks"
exec swift test --package-path "$(dirname "$0")" -Xswiftc -F"$F" -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xlinker -F"$F" -Xlinker -rpath -Xlinker "$F" "$@"
