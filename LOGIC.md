# How Grandpa reads your usage

The usage rules are in `Sources/TokenPet/Logic.swift`, as pure functions of (readings, now); the
app rules at the end are in `BarFit.swift`, `Onboarding.swift` (`StatusLineSetup`) and the
`MountainLedger` in `UsageModel.swift`. Every row below has a unit test (`./test.sh`,
`Tests/TokenPetTests/LogicTests.swift` for the usage rules, `AppTests.swift` for the app rules).

## Inputs

| Input | Where it comes from | Used for |
|---|---|---|
| Claude `five_hour`, `seven_day`: used %, reset time | Claude Code's status line JSON, saved by `bridge/statusline-bridge.sh` with its capture time | the carrier and Grandpa's state |
| Codex 5-hour (300 min) and weekly (10080 min) windows | newest `rate_limits` line in `~/.codex/sessions/**/*.jsonl` | the grandson's basket only |
| Output tokens with timestamps | `~/.claude/projects/**/*.jsonl` (`message.usage`) and Codex `token_count` events | shovel speed only |
| Tokens (input + output + cache writes) | the same Claude Code logs | the mountain only |

Nothing else: no network, no credentials, no saved limit state. Token counts never become a limit percentage.

## Limits → state (checked top to bottom)

| # | When | Then |
|---|---|---|
| 1 | No usable Claude reading (no file, corrupt or cut-off JSON, no window, percent missing or not a number) | **Don't know**: the bubble says so, the menu bar shows `?`, meters say "모름". Nothing is estimated. |
| 2 | A window's reset time has passed (reset ≤ now) | That window is new and empty: 0%, next reset unknown until Claude Code reports again |
| 3 | Any window at 100% | **Resting** until that window resets (the latest one if several are full; `?` if no reset time) |
| 4 | No 5-hour window, weekly window with a reset time (verified Ultra) | Day *d* = whole days since (weekly reset − 7 days), 0…6. Today's share = (weekly % − *d*·100/7) ÷ (100/7), never below 0. It only sets the pace (row 6); it never makes him rest |
| 5 | A reset (row 2) or a new day (row 4) less than 5 minutes ago | **Morning** stretch |
| 6a | Otherwise, weekly-only (row 4) | **Straining** ("ahead of today's share, take it slow") if today's share ≥ 100% · **steady** if ≥ 75% · **lively** otherwise. A high weekly % alone does not strain him |
| 6b | Otherwise, top = highest window %, pace = highest of (window % ÷ share of that window gone by, at least 12%) | **Straining** if top ≥ 80 or pace ≥ 110 · **steady** if pace ≥ 75 · **lively** otherwise |

The carrier is the limit that makes him rest: the 5-hour %, else the weekly %. The menu bar shows the same %.
The grandson's basket is Codex's own 5-hour %, else its weekly % (row 2 applies). Codex never stands in for Claude.

Row 4 in words: by the end of day *d* the fair use is (*d*+1)/7 of the week. Days you used less
carry over; days you used more make him sweat, but weekly use is bursty, so he naps only when the
weekly limit itself runs out (row 3), and the popover says when it resets. It needs no saved
"start of day" value, so restarts, sleep and several Macs cannot skew it.

## Shovel speed (RunCat-style)

| Smoothed output tokens/min, whole Mac | Level | Grandpa | Animation speed |
|---|---|---|---|
| < 50 | idle | leans on the shovel, chats with the magpie (yawns at night) | ×1 |
| 50 – 2,000 | low | digs slowly | ×0.6 |
| 2,000 – 8,000 | high | digs | ×1.0 |
| ≥ 8,000 | very high | digs fast, sweating | ×1.5 |

- Rate = output tokens stamped in the last 3 minutes ÷ 3 (future stamps ignored).
- Smoothing: exponential, time constant 60 s. A level drops only when the rate falls 20% under its bound, so it cannot flicker.
- The animation clock eases to the new speed (time constant 1.5 s); the pose never jumps.
- Resting and morning ignore the speed.

## Time

- Every rule compares absolute times (epoch seconds), so the time zone never changes a result.
  Only the printed clock times use this Mac's time zone (e.g. reset `1794164400` prints `월 04:00` in Seoul, `Sun 19:00` in UTC).
- Old readings are shown as they were, with their capture time: usage can only have grown since, unless a reset passed (row 2).
- A clock moved backwards changes nothing: readings stamped "in the future" still count, and smoothing ignores negative time.

## The mountain and the milestone

| When | Then |
|---|---|
| A log event newer than the last one counted | Its tokens (input + output + cache writes) are added once; the count and the newest counted time are saved, so a restart neither loses nor double-counts |
| First run | The week of logs already on disk is counted |
| Tokens reach the mountain's size (1 billion) | The cutscene is due (saved, survives a restart): the menu bar shows ✨, one notification per mountain, and the popover plays the cutscene once from the start when opened |
| "On to the next mountain" | The next mountain starts with the tokens beyond the size (Taihang, then Wangwu, then numbered) |

## Menu bar

| When | Then |
|---|---|
| Less than half of the item's width lies on any screen (macOS pushed it off a full menu bar; measured here at x = −4316 on a 1728-point screen) | **Hidden** |
| More than half of the item lies under the camera notch (the gap between the screen's two usable menu-bar areas) | **Hidden** |
| The item has no frame yet | No verdict; look again later |

Checked 2 s after launch and again 1 s after the item moves or the screens change.
The first time it is hidden, one notification says so (never again; saved).
The **mini window** setting: *when the menu bar is full* (default) shows a small floating window
with the same pet only while the item is hidden; *always*; or *never*. Opening the app again
(Finder, Spotlight, the notification) opens the popover; if the item is hidden it opens under the
mini window, which then shows even when set to never.

Drawing stops when nobody can see the pet: display asleep, user switched out, or neither the bar
item nor the mini window is on screen.

## Settings (UserDefaults domain `TokenPet`, shared by `swift run` and the app)

| Setting | Default |
|---|---|
| Language | System (Korean if the first preferred language is Korean, else English); or pinned 한국어 / English |
| Show the grandson (Codex) | On. Off hides him and his meters; his tokens still count toward the shovel speed |
| Mini window | When the menu bar is full |
| Open at login | **Off.** Only the user can turn it on (SMAppService, app bundle only); the app never registers itself |
| Hide from screen sharing | On |

## Claude Code setup

The app never edits `~/.claude/settings.json`. "Copy snippet" copies the bridge script into the
folder that holds `limits.json` and puts this on the clipboard, to paste into the top-level object:
`"statusLine": {"type": "command", "command": "sh ~/.claude/token-pet/statusline-bridge.sh"}`
(another folder gets `TOKENPET_DIR='…' sh '…/statusline-bridge.sh'`, quoted). The bridge reads the
JSON with `jq`, or with `plutil` on Macs without `jq` (before macOS 15); both save the same file.

## Not used (on purpose)

- Token budgets and "learned" 5-hour ceilings: a guess, wrong on a Mac with several accounts.
- Claude Code's "limit reached · resets 10pm" log messages: they mix accounts; the status line already says 100%.
- The separate Fable weekly limit: the status line does not report it.
