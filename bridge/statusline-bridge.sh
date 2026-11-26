#!/bin/sh
# TokenPet bridge for Claude Code's statusLine hook.
# Claude Code pipes a JSON object to this script after each response. We keep ONLY the
# documented `rate_limits` object (5-hour / 7-day used_percentage + resets_at) in
# $TOKENPET_DIR/limits.json. No prompts, paths, session ids, or credentials are stored,
# and nothing goes over the network. The payload names no account, and no local file says which
# account answered a session's last request, so the app tells accounts apart by the weekly window in
# the limits themselves (LOGIC.md "Accounts").
# A session redraws the limits of its last response until the next one. Only a change is a new reading:
# each session's last limits are kept as a SHA-256 hash (file named by a hash of the session id) in
# $TOKENPET_DIR/sessions/, and an unchanged redraw is not written.
# `--chain '<command>'` keeps a status line you already had: it gets the same JSON and its output is shown.
# Our own tools come only from system and Homebrew folders, not from whatever PATH Claude Code passes in;
# a chained status line still runs with that PATH. Session files older than 30 days are removed.
caller_path=$PATH
PATH=/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin; export PATH
dir="${TOKENPET_DIR:-$HOME/.claude/token-pet}"
input=$(cat)
# jq when installed (built into macOS 15+), otherwise plutil (every macOS)
if command -v jq >/dev/null 2>&1; then
  rl=$(printf '%s' "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
  pct=$(printf '%s' "$rl" | jq -r '.five_hour.used_percentage // empty' 2>/dev/null)
  week=$(printf '%s' "$rl" | jq -r '.seven_day.used_percentage // empty' 2>/dev/null)
  sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
else
  # plutil's handling of stdin (`-`) differs between supported macOS releases.
  # Use private files instead, so the no-jq path is stable on every supported macOS.
  input_file=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/tokenpet-bridge.XXXXXX") || exit 0
  limits_file=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/tokenpet-limits.XXXXXX") || exit 0
  pct_file=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/tokenpet-pct.XXXXXX") || exit 0
  sid_file=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/tokenpet-session.XXXXXX") || exit 0
  /bin/chmod 600 "$input_file" "$limits_file" "$pct_file" "$sid_file"
  trap '/bin/rm -f "$input_file" "$limits_file" "$pct_file" "$sid_file"' 0 1 2 15
  printf '%s' "$input" > "$input_file"
  plutil -extract rate_limits json -o "$limits_file" "$input_file" 2>/dev/null
  rl=$(/bin/cat "$limits_file")
  plutil -extract five_hour.used_percentage raw -o "$pct_file" "$limits_file" 2>/dev/null
  pct=$(/bin/cat "$pct_file")
  week=$(plutil -extract seven_day.used_percentage raw -o - "$limits_file" 2>/dev/null)
  # `plutil -extract` can print its missing-key diagnostic to stdout on older macOS releases;
  # do not let an optional session_id leak into a chained status line.
  case "$input" in *'"session_id"'*) plutil -extract session_id raw -o "$sid_file" "$input_file" 2>/dev/null ;; esac
  sid=$(/bin/cat "$sid_file")
  /bin/rm -f "$input_file" "$limits_file" "$pct_file" "$sid_file"
  trap - 0 1 2 15
fi
write_reading=1
if [ -n "$sid" ] && [ -n "$rl" ] && [ "$rl" != "null" ]; then
  session_hash=$(printf '%s' "$sid" | /usr/bin/shasum -a 256 | /usr/bin/cut -c1-24)
  session_dir="$dir/sessions"
  session_file="$session_dir/$session_hash"
  limits_hash=$(printf '%s' "$rl" | /usr/bin/shasum -a 256 | /usr/bin/cut -c1-64)
  # the last line: files from 0.3.7 and older also hold an account hash on the line before
  [ -f "$session_file" ] && [ "$(/usr/bin/tail -n 1 "$session_file" 2>/dev/null)" = "$limits_hash" ] && write_reading=0
  if [ "$write_reading" = 1 ]; then
    (umask 077; mkdir -p "$session_dir" && /bin/chmod 700 "$session_dir" &&
      printf '%s\n' "$limits_hash" > "$session_file.tmp.$$" && mv "$session_file.tmp.$$" "$session_file") 2>/dev/null
    /usr/bin/find "$session_dir" -type f -mtime +30 -exec /bin/rm -f {} + 2>/dev/null
  fi
fi
if [ "$write_reading" = 1 ] && [ -n "$rl" ] && [ "$rl" != "null" ]; then
  mkdir -p "$dir"
  printf '{"captured_at":%s,"rate_limits":%s}\n' "$(date +%s)" "$rl" > "$dir/limits.json.tmp" &&
    mv "$dir/limits.json.tmp" "$dir/limits.json"
fi
if [ "$1" = "--chain" ] && [ -n "$2" ]; then
  printf '%s' "$input" | PATH=$caller_path /bin/sh -c "$2"
  exit $?
fi
if [ -n "$pct" ]; then
  printf '🐾 5h %.0f%%' "$pct"
elif [ -n "$week" ]; then
  printf '🐾 week %.0f%%' "$week"
fi
exit 0
