# How Grandpa reads your usage

All of this is in `Sources/TokenPet/Logic.swift`, as pure functions of (readings, now).
Every row below has a unit test (`./test.sh`, `Tests/TokenPetTests/LogicTests.swift`).

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
| 4 | No 5-hour window, weekly window with a reset time (verified Ultra) | Day *d* = whole days since (weekly reset − 7 days), 0…6. Carrier = (weekly % − *d*·100/7) ÷ (100/7), never below 0. Carrier ≥ 100% → **resting** until the day ends |
| 5 | A reset (row 2) or a new day (row 4) less than 5 minutes ago | **Morning** stretch |
| 6 | Otherwise, top = highest window %, pace = highest of (window % ÷ share of that window gone by, at least 12%) | **Straining** if top ≥ 80 or pace ≥ 110 · **steady** if pace ≥ 75 · **lively** otherwise |

The carrier is the 5-hour %, else row 4's daily share, else the weekly %.
The grandson's basket follows rows 2 and 4 for Codex's own windows. Codex never stands in for Claude.

Row 4 in words: by the end of day *d* the fair use is (*d*+1)/7 of the week. Days you used less
carry over; days you used more show up as a fuller carrier. It needs no saved "start of day" value,
so restarts, sleep and several Macs cannot skew it.

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

## Not used (on purpose)

- Token budgets and "learned" 5-hour ceilings: a guess, wrong on a Mac with several accounts.
- Claude Code's "limit reached · resets 10pm" log messages: they mix accounts; the status line already says 100%.
- The separate Fable weekly limit: the status line does not report it.
