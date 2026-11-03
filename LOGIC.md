# How Grandpa reads your usage

The usage rules are in `Sources/TokenPet/Logic.swift`, as pure functions of (readings, now); the
app rules at the end are in `BarFit.swift`, `Onboarding.swift` (`StatusLineSetup`) and the
`MountainLedger` in `UsageModel.swift`. Every row below has a unit test (`./test.sh`,
`Tests/TokenPetTests/LogicTests.swift` for the usage rules, `AppTests.swift` for the app rules,
`FamilyTests.swift` for the family, the budgets and the connectors).

## Inputs

| Input | Where it comes from | Used for |
|---|---|---|
| Claude `five_hour`, `seven_day`: used %, reset time | Claude Code's status line JSON, saved by `bridge/statusline-bridge.sh` with its capture time | the meter of whoever watches Claude |
| Codex 5-hour (300 min) and weekly (10080 min) windows | newest `rate_limits` line in `~/.codex/sessions/**/*.jsonl` | the meter of whoever watches Codex |
| Gemini: nothing | Gemini CLI saves no limits or reset times on the Mac | its meter is always "don't know" |
| OpenAI API: this month's spend in USD | `GET api.openai.com/v1/organization/costs` from the first day of the month (UTC), with an Admin key from the Keychain, every 15 minutes | its meter: spend ÷ the monthly budget typed in Settings |
| DeepSeek API: balance only | `GET api.deepseek.com/user/balance` with its API key from the Keychain, every 15 minutes | shown as a balance; its meter is "don't know" (DeepSeek reports no spend) |
| Output tokens with timestamps | `~/.claude/projects/**/*.jsonl` (`message.usage`), Codex `token_count` events, Gemini CLI `~/.gemini/tmp/*/chats/session-*.json` | shovel speed only |
| Tokens: Claude input + output + cache writes; Codex input without the cached part + output; Gemini `total` | the same logs | the mountain only |

No saved limit state, and token counts never become a limit percentage. The network is used
only for an OpenAI or DeepSeek member you set up: the request carries your key (kept in the
login Keychain, never in a file or the settings) and nothing else leaves the Mac. The update check
(below) is the one other request.

## Limits → state (checked top to bottom)

The rows below read **Grandpa's AI** (Claude unless changed in Settings › Family). Its windows
are the 5-hour and weekly ones, or for a billed API the month's budget.

| # | When | Then |
|---|---|---|
| 1 | No usable reading (no file, corrupt or cut-off JSON, no window, percent missing or not a number; Gemini; DeepSeek; OpenAI without key, budget or answer) | **Don't know**: the bubble says so, the menu bar shows `?`, meters say "모름". Nothing is estimated. |
| 2 | A window's reset time has passed (reset ≤ now; for a budget, the month ended) | That window is new and empty: 0%, next reset unknown until the AI reports again |
| 3 | Any window at 100% | **Resting** until that window resets (the latest one if several are full; `?` if no reset time) |
| 4 | No 5-hour window, weekly window with a reset time (verified Ultra) | Day *d* = whole days since (weekly reset − 7 days), 0…6. Today's share = (weekly % − *d*·100/7) ÷ (100/7), never below 0. It only sets the pace (row 6); it never makes him rest |
| 5 | A reset (row 2) or a new day (row 4) less than 5 minutes ago | **Morning** stretch |
| 6a | Otherwise, weekly-only (row 4) | **Straining** ("ahead of today's share, take it slow") if today's share ≥ 100% · **steady** if ≥ 75% · **lively** otherwise. A high weekly % alone does not strain him |
| 6b | Otherwise, top = highest window %, pace = highest of (window % ÷ share of that window gone by, at least 12%) | **Straining** if top ≥ 80 or pace ≥ 110 · **steady** if pace ≥ 75 · **lively** otherwise |

The carrier is the limit that makes him rest: the 5-hour %, else the weekly %, else the month's
budget %. The menu bar shows the same %.

## Family

| When | Then |
|---|---|
| First run | Grandpa watches Claude, the grandson watches Codex (or nobody if "show the grandson" was turned off before) |
| An AI is given to a member who already has one, and another member had that AI | The two members swap: an AI is watched by one member at a time |
| Grandpa is set to nobody | Ignored: Grandpa always watches one AI |
| The son, the grandson or the neighbour's boy watches an AI | He stands in the scene with his own meter (heap of stone, basket, little basket): that AI's 5-hour %, else weekly %, else month's budget %, row 2 applies. Full = he sits down. Nothing to read = "don't know" and an empty meter |

Only Grandpa's AI sets his state and the menu bar; the others never stand in for him.

## Visitors (from the tale)

One at a time, at the left of the scene, with a speech bubble; Grandpa answers in his. Checked top
to bottom. Nobody comes while he doesn't know, or during the cutscene.

| When | Who | Says | Grandpa answers |
|---|---|---|---|
| Grandpa rests (row 3) | Zhisou, the clever old man of the river bend | "Told you so, ho ho! Not one blade of grass moved." | "Sons, then grandsons, on and on for ever. The mountain won't grow!" (子子孫孫無窮匱) |
| Within 10 minutes of a change of plan (who watches which AI, or which windows Grandpa's AI has), or in the first 6 hours of a new weekly window | His wife, doubting, until half the first mountain is gone | "And where will you dump all that earth?" | "Off the tail of the Bohai Sea, ho ho!" |
| The same, once half the first mountain is gone (or from the second mountain on) | His wife, cheering | "It really is shrinking! Go on, dear!" | "See? One shovel at a time." |

The plan is remembered in the settings, so the first run and a restart are not a change; a missing
reading is not a change either.

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
| Tokens reach the mountain's size (1 billion) | The cutscene is due (saved, survives a restart): the menu bar shows ✨, one notification per mountain, and the popover plays the cutscene once from the start when opened: Kua'e's two sons, sent by the Heavenly Emperor, rise out of the earth holding the mountain up and carry it off to the left (4.5 s) |
| "On to the next mountain" | The next mountain starts with the tokens beyond the size (Taihang, then Wangwu, then numbered) |

## Titles

Every token carried, all mountains together (`mountain index × size + tokens`, no new counter), earns a
rank. Roughly ×3 at first, then by whole mountains, so the first title comes in the first session and
the top one after months. The days column assumes ~10M counted tokens a day (a daily Claude Code user;
cache writes count; this Mac measured ~12M a day over 8 days of logs).

| # | Title (한국어) | Tokens in all | ~Days at 10M/day |
|---|---|---|---|
| 1 | Grandson with a Shovel (삽 든 손주) | 100k | the first hour |
| 2 | Carrier Bearer (지게꾼) | 1M | the first afternoon |
| 3 | Stone Breaker (돌 깨는 일꾼) | 10M | 1 |
| 4 | Basket Master (삼태기 장인) | 40M | 4 |
| 5 | Hauler to the Bohai Sea (발해까지 나르는 자) | 100M | 10 |
| 6 | Carver of Mount Taihang (태행산을 깎는 자) | 300M | 30 |
| 7 | Mover of Mount Wangwu (왕옥산을 옮기는 자) | 1B: Taihang is gone | 100 |
| 8 | Heir of Yugong (우공의 후계자) | 1.5B | 150 |
| 9 | One Who Moved Heaven (하늘도 감동한 자) | 2B: both mountains | 200 |
| 10 | Yugong Who Moved the Mountains (산을 옮긴 우공) | 3B | 300 |

| Achievement | Earned when |
|---|---|
| Full Carrier (지게 가득) | Grandpa's AI reports a window at 100% (he rests) |
| Seven Days of Digging (이레 연속 삽질) | Tokens from any local CLI on 7 local days in a row (the last 30 days are kept) |
| Kept to the Week (주간 한도 지킴이) | A weekly window ends, the next one starts (a start more than a day later; reset times wobble by seconds), and the one watched never reached 100% |
| Two Shovels (두 삽으로) | Two of Claude Code, Codex and Gemini CLI have tokens on the same local day |
| Up for the Dawn Reset (새벽 리셋을 지켜본 자) | The "morning" state (a reset in the last 5 minutes) is seen before 06:00 local time |

| When | Then |
|---|---|
| A rank above the last one celebrated | One celebration for the highest reached (the first run with a full log gets one, not six): confetti and the magpie in the popover until "Thanks, magpie", and one notification |
| A new achievement | The same, once |
| Limits unknown | No limit-based achievement is claimed |
| Restart | Ranks celebrated, achievements (with the time earned), active days and the watched week are saved in `titles.*` |
| Title card | The pixel scene, the title, tokens in all, mountains moved, achievements; no name, account or date. Saved as PNG only where you choose; nothing is sent |

## Title rewards

Each title adds one thing to the picture, automatically, and it stays (rewards = rank + 1, from the
tokens in all; nothing new is stored). Grandpa's face, hat and clothes never change: only his gear and
the world around him. Drawn in `assets/characters/yugong/YugongRewards.swift`; `YugongSheet <dir> --rewards`
renders every title before and after.

| # | Reward | Where it shows | From the tale (列子·湯問) |
|---|---|---|---|
| — | Before the first title the shovel is wooden, blade too | menu bar · scene | |
| 1 | The iron-bladed shovel | menu bar · scene | 叩石墾壤: breaking stone, turning soil |
| 2 | A teal tassel on the carrier's pole | menu bar · scene | 荷擔者: the one who carries |
| 3 | A pickaxe tucked in the carrier; broken stones at the dig face | menu bar · scene | 叩石 |
| 4 | Two baskets (삼태기), one full of earth, one tipped | scene | 箕畚 |
| 5 | The Bohai Sea on the horizon, with an islet of dumped earth | scene | 投諸渤海之尾 |
| 6 | Terraced fields, ripe, on the carved slope | scene | |
| 7 | The family's thatched house (smoke; a lit window at night) | scene | 懲山北之塞，出入之迂 |
| 8 | The family banner (농기); in the menu bar a white flag on the carrier | menu bar · scene | 子子孫孫無窮匱 |
| 9 | Two auspicious clouds, left of the sun (the speech bubble covers the right) | scene | 帝感其誠 |
| 10 | Golden shovel; an open road with a milestone; once, the finale | menu bar (shovel) · scene | 命夸娥氏二子負二山…無隴斷焉 |

| When | Then |
|---|---|
| Settings › *Hide background props* | The scene drops 3–9 and the road (sky, horizon, ground); the gear on Grandpa stays. The title card always shows everything earned |
| Someone stands where a prop goes | The prop takes the first clear spot of a few (the house moves to the mountain's foot when the grandson is out; with the son, one basket stands between him and Grandpa); with the whole family out, the least covered one |
| A title is celebrated | Its reward twinkles (four little stars) until "Thanks, magpie" |
| The top title, after its celebration and any mountain cutscene | The finale plays once from the start (golden sky, like the cutscene): Kua'e's two sons lift this mountain and a second one and carry them off in opposite directions, one east, one south (one west on screen, it is a side view), leaving the open road. "Walk the open road" ends it; `titles.finale` keeps it from playing again. The titles window's *Watch the finale again* replays it in the Yugong window |
| Demos | `--demo finale`; `--lifetime <tokens>` shows that many rewards |

## Menu bar

The item shows Grandpa and a number beside him. The number is the **headline** window (the
5-hour window, else the weekly one; also the carrier), in the style chosen in Settings:

| Setting | Shows (5-hour 24%, resets in 3 h 12 m at 04:40) |
|---|---|
| Percent used (default) | `24%` |
| Time to reset | `3h 12m` (`5d 2h` over a day, `12m` under an hour) |
| Reset time | `04:40` (`Mon 04:00` on another day) |
| None | nothing |

Before the style: `✨` while a mountain's cutscene is due, `?` without data, and while he rests
the time he starts again (as time left in the *time to reset* style). The time styles show the
percent when the reset time is unknown. **Grandpa in the menu bar** can be turned off; with no
number as well, Grandpa stays, so the item is never empty. The text is redrawn only when it
changes. The popover header shows the headline as `24% · 04:40`.

| When | Then |
|---|---|
| Less than half of the item's width lies on any screen (macOS pushed it off a full menu bar; measured here at x = −4316 on a 1728-point screen) | **Hidden** |
| More than half of the item lies under the camera notch (the gap between the screen's two usable menu-bar areas) | **Hidden** |
| The item has no frame yet | No verdict; look again later |

Checked 2 s after launch and again 1 s after the item moves or the screens change.

A click in a menu bar opens the popover under the mouse, on that display (`BarFit.clickAnchor`):
macOS 26 shows the item as Control Center copies on every display while the app's own item window
stays on one display or off-screen. With the mouse on the item itself, or not in a menu bar
(keyboard, VoiceOver), the popover opens from the item, or the mini window when the item is hidden.
The first time it is hidden, one notification says so (never again; saved).
The **mini window** setting: *when the menu bar is full* (default) shows a small floating window
with the same pet only while the item is hidden; *always*; or *never*. Opening the app again
(Finder, Spotlight, the notification) opens the popover; if the item is hidden it opens under the
mini window, or, with the mini window off, the Yugong window (the popover's scene in a window of
its own) opens instead.

The **Yugong window** remembers its frame; on opening, a frame whose display is gone moves to the
main screen (top right), and one partly off its screen is pulled fully onto it (`ScenePlace.fit`).

Drawing stops when nobody can see the pet: display asleep, user switched out, or neither the bar
item nor the mini window is on screen. The Yugong window's scene shows a still picture while the
window is closed, minimized or fully covered (occlusion), so its 8 fps timeline stops.

## Settings (UserDefaults domain `TokenPet`, shared by `swift run` and the app)

| Setting | Default |
|---|---|
| Language | System (macOS matches the preferred languages in order against English, Korean, Japanese and Simplified Chinese; Traditional Chinese falls through to the next one, else English); or pinned English / 한국어 / 日本語 / 简体中文. Applied at once |
| Check for updates | On: at most one GitHub request a day (a failed one counts; a clock moved back asks again; never under `swift run`). A newer, unskipped version shows a popover row and one notification per version. Off: no request at all |
| Family | Grandpa: Claude · grandson: Codex · son and neighbour's boy: nobody. Every AI's tokens count toward the shovel speed and the mountain whoever watches it |
| OpenAI monthly budget | Not set (its meter says "don't know" until a budget and an Admin key are given) |
| API keys (OpenAI, DeepSeek) | None. Stored only in the login Keychain (`dev.yugongpet.api.*`) |
| Menu bar number | Percent used |
| Grandpa in the menu bar | On |
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
