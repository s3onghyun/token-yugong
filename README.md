# TokenPet (prototype): Grandpa Yugong

Grandpa Yugong (우공 할아버지), from the Liezi tale of the old man who moved the mountains,
lives in your Mac menu bar and shovels your Claude Code tokens:

- **Working pace**: lively, steady or straining, from how fast you are using the window
  compared with the time left before it resets.
- **Shovel speed** (RunCat-style): how many output tokens Claude Code and Codex are generating on
  this Mac right now. Idle = he leans on the shovel and chats; faster = faster digs; very fast = sweat.
- **No data = "don't know"**: without Claude Code's status-line numbers he says so; nothing is guessed.
- **The carrier (지게) is the 5-hour meter**: earth heaps up in his basket. When it is full he
  sets it down and naps, showing when he starts again ("09:00에 다시 퍼요").
- **Reset**: a morning stretch, and he picks the shovel back up.
- **Accounts without a 5-hour window** (verified Ultra): the carrier fills with today's fair
  share of the weekly limit (1/7 of the week, unused days carry over); full = he naps until the next day starts.
  No 5-hour meter is ever invented.
- **The mountain** in the popover erodes with every token he has ever shovelled (kept on this
  Mac). When a whole mountain is gone, heaven is moved and carries it away (cutscene), and the
  next mountain appears.
- **Codex** is his grandson, carrying a second basket.
- Habits: chatting with his magpie, wiping sweat, stretching his back, yawning at night.

Two art styles of the same poses: **pixel** (default) and **ink** (brush/ink-wash vector).

## Run

```sh
swift run --package-path data/token-pet-proto/app -c release TokenPet
```

Useful flags: `--demo lively|steady|straining|resting|morning|cutscene|cycle`, `--tempo idle|low|high|veryHigh`,
`--weekly-only` (demo an account with no 5-hour window), `--style pixel|ink`, `--lang en|ko`,
`--stage` (menu-bar item and popover in one window), `--render <dir>` (PNG stills),
`--scan-report` (prints what it read). Older flag names (`full`, `asleep`, `stretch`) still work.

Character sheets: `swift run --package-path data/token-pet-proto/app -c release YugongSheet <dir> [--scenes]`.

Tests: `./test.sh` (the rules are in [LOGIC.md](LOGIC.md)).

Nothing is installed: no login item, nothing copied to /Applications. Quit from the popover.

## Where the numbers come from

1. **Official Claude limits (best):** Claude Code passes `rate_limits.five_hour` and
   `rate_limits.seven_day` (used %, reset time) to its status line command; either window may be
   absent. Point your status line at `bridge/statusline-bridge.sh`, which saves only that object to
   `~/.claude/token-pet/limits.json`:

   ```json
   { "statusLine": { "type": "command", "command": "sh /path/to/bridge/statusline-bridge.sh" } }
   ```

2. **Codex:** the `rate_limits` that Codex CLI writes into `~/.codex/sessions/**/*.jsonl`.
3. **Shovel speed and the mountain:** token counts from `~/.claude/projects/**/*.jsonl` and Codex
   `token_count` events. These never become a limit percentage.

No network calls, no credentials read. Local state (UserDefaults domain `TokenPet`): the mountain
ledger (`mountain.*`), the chosen style and the screen-share setting. `defaults delete TokenPet` clears it.

## License

App code: MIT (`LICENSE`). Characters under `assets/`: separate license
(`assets/LICENSE.md`); see `assets/PROVENANCE.md` for how each asset was made.
