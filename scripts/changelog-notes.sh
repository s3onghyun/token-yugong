#!/bin/sh
# Print the changelog body for a released version, without its heading.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
version=${1:?usage: changelog-notes.sh VERSION}

awk -v version="$version" '
  index($0, "## " version " (") == 1 { found = 1; next }
  found && /^## / { exit }
  found { print }
  END { if (!found) exit 1 }
' "$root/CHANGELOG.md"
