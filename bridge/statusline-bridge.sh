#!/bin/sh
# TokenPet bridge for Claude Code's statusLine hook.
# Claude Code pipes a JSON object to this script after each response. We keep ONLY the
# documented `rate_limits` object (5-hour / 7-day used_percentage + resets_at) in
# $TOKENPET_DIR/limits.json. No prompts, paths, session ids, or credentials are stored,
# and nothing goes over the network. To tell Claude accounts apart, it adds a short SHA-256 hash of
# the signed-in account's id (oauthAccount.accountUuid in .claude.json); the id itself is never stored.
# A status-line session is pinned to that hash on its first reply.  This matters after /login: an old
# Claude Code session can redraw its old numbers, but it must not be relabelled as the newly signed-in account.
# Only SHA-256 hashes of the session id and account id are kept locally in $TOKENPET_DIR/sessions/.
# `--chain '<command>'` keeps a status line you already had: it gets the same JSON and its output is shown.
dir="${TOKENPET_DIR:-$HOME/.claude/token-pet}"
cfg="${CLAUDE_CONFIG_DIR:+$CLAUDE_CONFIG_DIR/.claude.json}"
cfg="${cfg:-$HOME/.claude.json}"
input=$(cat)
# jq when installed (built into macOS 15+), otherwise plutil (every macOS)
if command -v jq >/dev/null 2>&1; then
  rl=$(printf '%s' "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
  pct=$(printf '%s' "$rl" | jq -r '.five_hour.used_percentage // empty' 2>/dev/null)
  week=$(printf '%s' "$rl" | jq -r '.seven_day.used_percentage // empty' 2>/dev/null)
  sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
  uuid=$(jq -r '.oauthAccount.accountUuid // empty' "$cfg" 2>/dev/null)
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
  uuid=$(plutil -extract oauthAccount.accountUuid raw -o - "$cfg" 2>/dev/null)
  /bin/rm -f "$input_file" "$limits_file" "$pct_file" "$sid_file"
  trap - 0 1 2 15
fi
account=""
[ -n "$uuid" ] && account=$(printf '%s' "$uuid" | /usr/bin/shasum -a 256 | /usr/bin/cut -c1-12)
# `oauthAccount` is global to Claude Code, not to the session which produced this payload.  Remember
# which account a status-line session first belonged to, using hashes only, so an old session's redraw
# remains an old-account reading after /login.
if [ -n "$sid" ]; then
  session_hash=$(printf '%s' "$sid" | /usr/bin/shasum -a 256 | /usr/bin/cut -c1-24)
  session_dir="$dir/sessions"
  session_file="$session_dir/$session_hash"
  if [ -f "$session_file" ]; then
    mapped_account=$(/bin/cat "$session_file" 2>/dev/null)
    case "$mapped_account" in
      ???????????? )
        case "$mapped_account" in
          *[!0123456789abcdef]* ) ;;
          * ) account="$mapped_account" ;;
        esac
        ;;
    esac
  elif [ -n "$account" ]; then
    (umask 077; mkdir -p "$session_dir" && /bin/chmod 700 "$session_dir" &&
      printf '%s\n' "$account" > "$session_file.tmp.$$" && mv "$session_file.tmp.$$" "$session_file") 2>/dev/null
  fi
fi
if [ -n "$rl" ] && [ "$rl" != "null" ]; then
  mkdir -p "$dir"
  printf '{"captured_at":%s,%s"rate_limits":%s}\n' "$(date +%s)" "${account:+\"account\":\"$account\",}" "$rl" > "$dir/limits.json.tmp" &&
    mv "$dir/limits.json.tmp" "$dir/limits.json"
fi
if [ "$1" = "--chain" ] && [ -n "$2" ]; then
  printf '%s' "$input" | sh -c "$2"
  exit $?
fi
if [ -n "$pct" ]; then
  printf '🐾 5h %.0f%%' "$pct"
elif [ -n "$week" ]; then
  printf '🐾 week %.0f%%' "$week"
fi
exit 0
