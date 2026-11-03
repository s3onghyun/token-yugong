# Yugong Pet: Grandpa Yugong shovels your Claude tokens

[한국어](README.ko.md)

![Grandpa Yugong in the popover, going through his states](docs/demo.gif)

Grandpa Yugong (우공 할아버지), from the old tale of the ninety-year-old man who moved the
mountains one shovel at a time, lives in your Mac menu bar and shows your Claude Code usage:

- **The carrier (지게) is your 5-hour limit.** Earth heaps up in his A-frame carrier. When it is
  full he sits down and naps, the menu bar counts down to the reset, and one notification says so
  (another when it resets). A used-up weekly limit is a long rest under a full moon.

  ![Resting after the 5-hour limit (crescent) and the weekly limit (full moon)](docs/limit-reached.png)

- **Accounts with only a weekly limit** (verified Ultra): the carrier is the weekly limit, and he naps
  only when it runs out. Today's fair share (1/7 of the week, unused days carry over) sets his pace:
  past it he sweats and asks you to take it slow. No 5-hour meter is ever invented.
- **His pace** (RunCat-style): he digs faster when tokens flow faster on this Mac, leans on his
  shovel and chats with his magpie when it is quiet, and strains when you are heading for the limit.
- **The mountain** wears down with every token you have ever used (kept on this Mac). Carry a
  whole mountain away and heaven is moved: Kua'e's two giant sons carry it off, then the next
  mountain.
- **The rest of the tale.** His wife drops by when you change plans and at a new week to ask
  where all that earth will go (and cheers once half the mountain is gone); Zhisou comes to laugh
  when the limit runs out, and Grandpa answers him as in the Liezi.
- **The family.** You pick which AI Grandpa watches (Claude by default). His son, his grandson
  and the neighbour's boy can each watch another one: Codex, Gemini CLI, or the OpenAI or
  DeepSeek API (a monthly budget instead of a limit). The grandson watches Codex by default.
- **No data, no guessing.** Until an AI reports its limits, whoever watches it says he doesn't
  know. Gemini CLI keeps no limits on the Mac and DeepSeek reports only a balance, so for those
  he always says so.
- **Titles.** Every token you carry earns a rank, from *Grandson with a Shovel* (the first hour)
  to *Yugong Who Moved the Mountains* (months), plus a few achievements (a 7-day streak, a week
  kept under the limit, two AIs in one day...). The magpie brings the news with pixel confetti;
  the titles window lists them all and saves a shareable title card (PNG, no personal data).
- **Title rewards.** Each title adds one thing to the picture, and it stays: the wooden shovel gets its
  iron blade, then a tassel, a pickaxe, baskets, the Bohai Sea, terraced fields, the family house, the
  family banner, auspicious clouds, and at the top a golden shovel, an open road and a one-time finale
  in which Kua'e's sons carry both mountains off. Five of them show in the menu bar too. Settings ›
  *Hide background props* keeps only Grandpa's gear.

  ![Every title reward, before and after](docs/title-rewards.png)

All of it is pixel art: the menu-bar sprite, the popover scene and the app icon.

## Install

Needs macOS 13 or later.

### Download the app

1. Download `YugongPet-<version>-macos-universal.zip` and its `.sha256` file from the latest
   [GitHub Release](https://github.com/s3onghyun/token-yugong/releases).
2. In Terminal, verify the download (replace `<version>` with the release version):

   ```sh
   shasum -a 256 -c YugongPet-<version>-macos-universal.zip.sha256
   ```

3. Double-click the ZIP, then move `YugongPet.app` to `/Applications`.
4. The app is ad-hoc signed but **not notarized** yet. On its first launch, Control-click the app
   and choose **Open**, then choose **Open** again. If macOS blocks it first, go to **System
   Settings → Privacy & Security** and choose **Open Anyway**. Notarization will be added in a
   future release.

### Build from source

For a local build, install the Swift toolchain (Xcode or the Command Line Tools), then:

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
The status line only reports successful responses, so it stops at 99% when a limit runs out; the
app also reads the refusal Claude Code writes to its own session log (`usage_limit_reached`, with
the window and reset time) to show 100% and let Grandpa rest.

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
Keychain only. These two and the once-a-day update check (below) are the only times the app
uses the network.

## The Yugong window

Click Grandpa in the menu bar for the popover: the scene, the mountain, his title and every meter.
The first launch points at him once ("Click Grandpa to see his mountain"). The popover's **Window**
button opens the same scene in a window of its own that stays on the desktop:

![The Yugong window](docs/yugong-window.png)

Drag it anywhere (another display too, a vertical one included) and drag its corner to resize: the
content scales and keeps its proportions. The ⋯ button in its title bar (or a right-click) picks
small, medium or large, a normal window, *always on top* or *on the desktop* (under every app
window, on every Space), and the opacity. Esc or the close button hides it. Size, place, level
and opacity are remembered; if its display is gone, it comes back on the main screen. Settings ›
*Open the Yugong window when the app starts* (off by default) opens it at launch, and with *Open at
login*, at login. While the window is closed or covered the scene stops drawing (no CPU).

## When the menu bar is full

macOS quietly hides menu-bar icons that do not fit, or puts them behind the camera notch.
Grandpa notices, tells you once with a notification, and moves into a small floating window
(Grandpa at twice the bar size with the number; click for the popover on that display, drag it anywhere,
right-click for the Yugong window or to hide it). Settings › Mini window: *when the menu bar is full*
(default), *always* or *never*. Opening the app again always brings him up: the popover, or the
Yugong window when the bar has no room and the mini window is off.

## Settings

Gear button in the popover: language (System, English, 한국어, 日本語, 简体中文; it changes at once, no
restart), the menu-bar number (percent used,
time to reset, reset time or none) and whether Grandpa is shown next to it, the family (which AI
each member watches, the OpenAI budget, API keys), mini window, open at login (off by default, opt-in only), the Yugong window at start, update checks, and the guide. Everything is stored in the
UserDefaults domain `TokenPet`; `defaults delete TokenPet` resets it, including the mountain.

The Japanese and Chinese texts are AI-assisted translations; corrections are welcome (each string is
one `L.t(en, ko, ja, zh)` call, and `./test.sh` fails on a missing or wrong-script translation).

## Updates

Once a day the app asks GitHub for the latest release: one HTTPS GET to
`api.github.com/repos/s3onghyun/token-yugong/releases/latest`, with only `User-Agent: YugongPet/<version>`,
`Accept` and a fixed `Accept-Language: en`, no cookies and no cache. Nothing about you or your usage is
sent, and there is no telemetry. When a newer version is out, the popover shows a row with **Release
page** and **Skip this version**, and you get one notification for that version. The app never
downloads or installs anything itself: download the new ZIP, check its `.sha256` and replace the app
as in [Install](#install). Settings › *Check for updates (once a day)* turns it off; *Check now* asks
at once.

## How the numbers become a pet

Every rule is in one page, [LOGIC.md](LOGIC.md), and every rule has a unit test (`./test.sh`).
In short: official limits only, the reset time decides when a window starts over, and the
weekly-only share needs no saved state, so restarts and several Macs give the same answer.

## For development

`swift run -c release TokenPet` with flags: `--demo lively|steady|straining|resting|morning|cutscene|cycle`,
`--lifetime <tokens>`, `--award rank:<0-9>|feat:<name>`, `--titles` (open the titles window), `--window` (open the Yugong window),
`--tempo idle|low|high|veryHigh`, `--visitor wifeDoubting|wifeCheering|zhisou`, `--weekly-only`, `--lang en|ko|ja|zh|pseudo`
(`pseudo`: every string about 40% longer and accented, to find truncation with `--render`),
`--stage` (bar item and popover in one window, for recording), `--allow-capture`, `--open`,
`--settings`, `--guide`, `--pretend-hidden` (try the mini-window fallback),
`--render <dir>` (PNG stills), `--icon-set <dir>`, `--scan-report` (prints what it read),
`--anim-stats`. `TOKENPET_PREFS=<domain>` keeps a test run out of your settings.

Character sheets: `swift run -c release YugongSheet <dir> [--scenes] [--family] [--visitors]`.

## License

- App code (`Sources/`, `bridge/`, `scripts/`, `Tests/`): MIT, see [LICENSE](LICENSE).
- Grandpa Yugong and everything under `assets/` (including `docs/demo.gif`): all rights reserved,
  with a personal-use grant, see [assets/LICENSE.md](assets/LICENSE.md) and
  [assets/PROVENANCE.md](assets/PROVENANCE.md).

[Changelog](CHANGELOG.md)
