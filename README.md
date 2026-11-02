# Yugong Pet: Grandpa Yugong shovels your Claude tokens

[한국어](README.ko.md)

![Grandpa Yugong in the popover, going through his states](docs/demo.gif)

Grandpa Yugong (우공 할아버지), from the old tale of the ninety-year-old man who moved the
mountains one shovel at a time, lives in your Mac menu bar and shows your Claude Code usage:

- **The carrier (지게) is your 5-hour limit.** Earth heaps up in his A-frame carrier. When it is
  full he sits down and naps, and the menu bar shows when he starts again.
- **Accounts with only a weekly limit** (verified Ultra): the carrier is the weekly limit, and he naps
  only when it runs out. Today's fair share (1/7 of the week, unused days carry over) sets his pace:
  past it he sweats and asks you to take it slow. No 5-hour meter is ever invented.
- **His pace** (RunCat-style): he digs faster when tokens flow faster on this Mac, leans on his
  shovel and chats with his magpie when it is quiet, and strains when you are heading for the limit.
- **The mountain** wears down with every token you have ever used (kept on this Mac). Carry a
  whole mountain away and heaven is moved: a short cutscene, then the next mountain.
- **The family.** You pick which AI Grandpa watches (Claude by default). His son, his grandson
  and the neighbour's boy can each watch another one: Codex, Gemini CLI, or the OpenAI or
  DeepSeek API (a monthly budget instead of a limit). The grandson watches Codex by default.
- **No data, no guessing.** Until an AI reports its limits, whoever watches it says he doesn't
  know. Gemini CLI keeps no limits on the Mac and DeepSeek reports only a balance, so for those
  he always says so.

All of it is pixel art: the menu-bar sprite, the popover scene and the app icon.

## Install

Needs macOS 13 or later and the Swift toolchain (Xcode or the Command Line Tools).

```sh
./scripts/bundle.sh          # builds build/YugongPet.app (ad-hoc signed, not notarized)
open build/YugongPet.app     # or move it to /Applications first
```

The first launch shows a short guide. Its last page has a **Copy snippet** button for the
Claude Code status line (below). Quit from the popover.

Or run without a bundle: `swift run -c release TokenPet` (no notifications or open-at-login there).

## Connect Claude Code

Claude Code hands its status-line command your official limits (`rate_limits.five_hour` and
`rate_limits.seven_day`: used %, reset time). The bridge script saves only that object to
`~/.claude/token-pet/limits.json`; no prompts, paths or session ids, no network.

**Copy snippet** in the guide (or Settings › How it works) copies the bridge into
`~/.claude/token-pet/` and this onto the clipboard. Paste it into the top-level object of
`~/.claude/settings.json` yourself; the app never edits that file:

```json
"statusLine": {
  "type": "command",
  "command": "sh ~/.claude/token-pet/statusline-bridge.sh"
}
```

Already have a status line? Keep it and make its first line
`input=$(cat); printf '%s' "$input" | sh ~/.claude/token-pet/statusline-bridge.sh >/dev/null`,
then read the JSON from `$input`.

The bridge uses `jq` when present (built into macOS 15+) and `plutil` otherwise.
Codex needs no setup: its own logs (`~/.codex/sessions`) carry its limits. Gemini CLI needs none
either (its tokens are read from `~/.gemini/tmp`).

**API budgets.** For the OpenAI API, give a member OpenAI in Settings › Family, type a monthly
budget in USD and paste an **Admin key** (OpenAI reports costs only to Admin keys). The meter is
this month's spend ÷ the budget, asked every 15 minutes. For DeepSeek, paste an API key to see the
balance; DeepSeek does not report spend, so its meter says "don't know". Keys go into the login
Keychain only. These two are the only times the app uses the network.

## When the menu bar is full

macOS quietly hides menu-bar icons that do not fit, or puts them behind the camera notch.
Grandpa notices, tells you once with a notification, and moves into a small floating window
(drag it anywhere; right-click to hide it). Settings › Mini window: *when the menu bar is full*
(default), *always* or *never*. Opening the app again always brings him up.

## Settings

Gear button in the popover: language (system, 한국어, English), the menu-bar number (percent used,
time to reset, reset time or none) and whether Grandpa is shown next to it, the family (which AI
each member watches, the OpenAI budget, API keys), mini window, open at login (off by default, opt-in only), and the guide. Everything is stored in the
UserDefaults domain `TokenPet`; `defaults delete TokenPet` resets it, including the mountain.

## How the numbers become a pet

Every rule is in one page, [LOGIC.md](LOGIC.md), and every rule has a unit test (`./test.sh`).
In short: official limits only, the reset time decides when a window starts over, and the
weekly-only share needs no saved state, so restarts and several Macs give the same answer.

## For development

`swift run -c release TokenPet` with flags: `--demo lively|steady|straining|resting|morning|cutscene|cycle`,
`--tempo idle|low|high|veryHigh`, `--weekly-only`, `--lang en|ko`,
`--stage` (bar item and popover in one window, for recording), `--allow-capture`, `--open`,
`--settings`, `--guide`, `--pretend-hidden` (try the mini-window fallback),
`--render <dir>` (PNG stills), `--icon-set <dir>`, `--scan-report` (prints what it read),
`--anim-stats`. `TOKENPET_PREFS=<domain>` keeps a test run out of your settings.

Character sheets: `swift run -c release YugongSheet <dir> [--scenes]`.

## License

- App code (`Sources/`, `bridge/`, `scripts/`, `Tests/`): MIT, see [LICENSE](LICENSE).
- Grandpa Yugong and everything under `assets/` (including `docs/demo.gif`): all rights reserved,
  with a personal-use grant, see [assets/LICENSE.md](assets/LICENSE.md) and
  [assets/PROVENANCE.md](assets/PROVENANCE.md).

[Changelog](CHANGELOG.md)
