#!/bin/sh
# TokenPet bridge for Claude Code's statusLine hook.
# Claude Code pipes a JSON object to this script after each response. We keep ONLY the
# documented `rate_limits` object (5-hour / 7-day used_percentage + resets_at) in
# $TOKENPET_DIR/limits.json. No prompts, paths, session ids, or credentials are stored,
# and nothing goes over the network.
dir="${TOKENPET_DIR:-$HOME/.claude/token-pet}"
input=$(cat)
rl=$(printf '%s' "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
if [ -n "$rl" ] && [ "$rl" != "null" ]; then
  mkdir -p "$dir"
  printf '{"captured_at":%s,"rate_limits":%s}\n' "$(date +%s)" "$rl" > "$dir/limits.json.tmp" &&
    mv "$dir/limits.json.tmp" "$dir/limits.json"
fi
pct=$(printf '%s' "$rl" | jq -r '.five_hour.used_percentage // empty' 2>/dev/null)
[ -n "$pct" ] && printf '🐾 5h %.0f%%' "$pct"
exit 0
