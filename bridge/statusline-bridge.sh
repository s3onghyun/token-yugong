#!/bin/sh
# Token Yugong's status line for Claude Code. It shows this session's own 5-hour (or weekly) percentage from the
# JSON Claude Code pipes in, and writes nothing: the app does not read status lines. It asks Claude Code's
# `/usage` per profile instead, because a status line names no account (LOGIC.md "Accounts").
# `--chain '<command>'` keeps a status line you already had: it gets the same JSON and its output is shown.
# Our own tools come only from system and Homebrew folders, not from whatever PATH Claude Code passes in;
# a chained status line still runs with that PATH.
caller_path=$PATH
PATH=/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin; export PATH
input=$(cat)
if [ "$1" = "--chain" ] && [ -n "$2" ]; then
  printf '%s' "$input" | PATH=$caller_path /bin/sh -c "$2"
  exit $?
fi
# jq when installed (built into macOS 15+), otherwise plutil (every macOS)
if command -v jq >/dev/null 2>&1; then
  pct=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
  week=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
else
  # plutil's handling of stdin (`-`) differs between supported macOS releases, so use a private file.
  input_file=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/tokenpet-bridge.XXXXXX") || exit 0
  /bin/chmod 600 "$input_file"
  trap '/bin/rm -f "$input_file"' 0 1 2 15
  printf '%s' "$input" > "$input_file"
  # `plutil -extract` can print its missing-key diagnostic to stdout on older macOS releases: keep numbers only.
  pct=$(plutil -extract rate_limits.five_hour.used_percentage raw -o - "$input_file" 2>/dev/null | grep -E '^[0-9.]+$')
  week=$(plutil -extract rate_limits.seven_day.used_percentage raw -o - "$input_file" 2>/dev/null | grep -E '^[0-9.]+$')
fi
if [ -n "$pct" ]; then
  printf '🐾 5h %.0f%%' "$pct"
elif [ -n "$week" ]; then
  printf '🐾 week %.0f%%' "$week"
fi
exit 0
