#!/bin/sh
# TokenPet bridge for Claude Code's statusLine hook.
# Claude Code pipes a JSON object to this script after each response. We keep ONLY the
# documented `rate_limits` object (5-hour / 7-day used_percentage + resets_at) in
# $TOKENPET_DIR/limits.json. No prompts, paths, session ids, or credentials are stored,
# and nothing goes over the network. To tell Claude accounts apart, it adds a short SHA-256 hash of
# the signed-in account's id (oauthAccount.accountUuid in .claude.json); the id itself is never stored.
# `--chain '<command>'` keeps a status line you already had: it gets the same JSON and its output is shown.
dir="${TOKENPET_DIR:-$HOME/.claude/token-pet}"
cfg="${CLAUDE_CONFIG_DIR:+$CLAUDE_CONFIG_DIR/.claude.json}"
cfg="${cfg:-$HOME/.claude.json}"
input=$(cat)
# jq when installed (built into macOS 15+), otherwise plutil (every macOS)
if command -v jq >/dev/null 2>&1; then
  rl=$(printf '%s' "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
  pct=$(printf '%s' "$rl" | jq -r '.five_hour.used_percentage // empty' 2>/dev/null)
  uuid=$(jq -r '.oauthAccount.accountUuid // empty' "$cfg" 2>/dev/null)
else
  # plutil's handling of stdin (`-`) differs between supported macOS releases.
  # Use private files instead, so the no-jq path is stable on every supported macOS.
  input_file=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/tokenpet-bridge.XXXXXX") || exit 0
  limits_file=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/tokenpet-limits.XXXXXX") || exit 0
  pct_file=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/tokenpet-pct.XXXXXX") || exit 0
  /bin/chmod 600 "$input_file" "$limits_file" "$pct_file"
  trap '/bin/rm -f "$input_file" "$limits_file" "$pct_file"' 0 1 2 15
  printf '%s' "$input" > "$input_file"
  plutil -extract rate_limits json -o "$limits_file" "$input_file" 2>/dev/null
  rl=$(/bin/cat "$limits_file")
  plutil -extract five_hour.used_percentage raw -o "$pct_file" "$limits_file" 2>/dev/null
  pct=$(/bin/cat "$pct_file")
  uuid=$(plutil -extract oauthAccount.accountUuid raw -o - "$cfg" 2>/dev/null)
  /bin/rm -f "$input_file" "$limits_file" "$pct_file"
  trap - 0 1 2 15
fi
account=""
[ -n "$uuid" ] && account=$(printf '%s' "$uuid" | /usr/bin/shasum -a 256 | /usr/bin/cut -c1-12)
if [ -n "$rl" ] && [ "$rl" != "null" ]; then
  mkdir -p "$dir"
  printf '{"captured_at":%s,%s"rate_limits":%s}\n' "$(date +%s)" "${account:+\"account\":\"$account\",}" "$rl" > "$dir/limits.json.tmp" &&
    mv "$dir/limits.json.tmp" "$dir/limits.json"
fi
if [ "$1" = "--chain" ] && [ -n "$2" ]; then
  printf '%s' "$input" | sh -c "$2"
  exit $?
fi
[ -n "$pct" ] && printf '🐾 5h %.0f%%' "$pct"
exit 0
