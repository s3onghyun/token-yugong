# Changelog

## Unreleased

## 0.2.0 (2026-11-03)

### Added
- The family: pick which AI Grandpa watches, and give his son, his grandson and the neighbour's
  boy one each (Settings › Family). Two new pixel characters: the son, breaking rock with a
  pickaxe, and the neighbour's seven-year-old with 색동 sleeves and a little basket
  (`YugongSheet --family` draws their sheet).
- The rest of the tale, three more pixel characters (`YugongSheet --visitors` draws their sheet):
  Yugong's wife, who comes when the plan or the family changes and at a new week to ask where all
  that earth will go, and cheers once half the mountain is gone; Zhisou, who comes to laugh when
  the limit runs out and gets Grandpa's 子子孫孫 answer; and Kua'e's two giant sons, who now carry
  the mountain off in the milestone cutscene. `--visitor` shows one in a demo.
- Gemini CLI: its tokens count for the shovel speed and the mountain; its meter says "don't know"
  because Gemini CLI keeps no limits on the Mac.
- API budgets: the OpenAI API's spend this month against a monthly budget (Costs API, Admin key);
  the DeepSeek API's balance (it reports no spend, so its meter says "don't know"). Keys are kept
  in the login Keychain; these are the app's only network requests.
- Codex and Gemini CLI tokens now also wear down the mountain.
- Menu-bar number setting: percent used (default, `24%`), time to reset (`3h 12m`), reset time
  (`Mon 04:00`) or none; and Grandpa on or off beside it (the item is never left empty). The
  number is the 5-hour window, else the weekly one. The popover header shows it as `24% · Mon 04:00`.

### Changed
- "Show the grandson (Codex)" became Settings › Family; turning it off before carries over.
- Weekly-only accounts: Grandpa naps only when the weekly limit is used up, never just because
  today's share (1/7 of the week) is spent. Weekly use is bursty, and a nap on day one was too
  strict. The carrier and the menu bar now show the weekly %; today's share sets his pace (past it
  he sweats: "ahead of today's share, take it slow"), and the popover says when the week resets.
  Codex's basket follows the same rule.

### Removed
- The ink-wash style. Grandpa Yugong, and every character after him, is pixel art only: the
  style picker in the popover, the `--style` flag and the ink drawing code are gone.

### Release
- First public downloadable build: a universal macOS app archive, ad-hoc signed but not notarized.
- GitHub Actions builds and tests every push and pull request, and version tags publish a ZIP with
  a SHA-256 checksum.

## 0.1.0 (2026-11-02)

First version meant for daily use.

### Added
- App bundle: `scripts/bundle.sh` builds `build/YugongPet.app` (ad-hoc signed, not notarized)
  with an original pixel app icon of Grandpa Yugong and his A-frame carrier.
- First-run guide: the tale, what the carrier, pace, mountain and grandson mean, and Claude Code
  status-line setup with a **Copy snippet** button. The app never edits `~/.claude/settings.json`.
- Full menu bar: detects when macOS pushes the icon off-screen or behind the notch, says so once
  with a notification, and shows a small floating mini window (setting: when full / always / never).
  Opening the app again always brings Grandpa up.
- Settings, saved: language (system / 한국어 / English), show the grandson (Codex), mini window,
  open at login (off by default, opt-in via SMAppService).
- Mountain milestone: ✨ in the menu bar, one notification per mountain, and the cutscene plays once
  from the start when the popover opens.
- Bridge falls back to `plutil` on Macs without `jq` (macOS 13 and 14).
- Tests for the new rules (57 tests in total); README in English and Korean; this changelog.

### Changed
- One settings domain (`TokenPet`) whether started with `swift run` or as the app, so mountain
  progress carries over. `TOKENPET_PREFS` picks another domain for test runs.
- Usage logic from the verification round (see LOGIC.md): no guessed budgets or "learned" limits,
  "don't know" without data, carry-over daily share for weekly-only accounts, RunCat-style pace,
  drawing paused when nobody can see the pet.

### Licenses
- Code: MIT. Character art (`assets/`, `docs/demo.gif`): all rights reserved, personal-use grant.
