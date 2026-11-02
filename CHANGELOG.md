# Changelog

## Unreleased

### Added
- Menu-bar number setting: percent used (default, `24%`), time to reset (`3h 12m`), reset time
  (`Mon 04:00`) or none; and Grandpa on or off beside it (the item is never left empty). The
  number is the 5-hour window, else the weekly one. The popover header shows it as `24% · Mon 04:00`.

### Changed
- Weekly-only accounts: Grandpa naps only when the weekly limit is used up, never just because
  today's share (1/7 of the week) is spent. Weekly use is bursty, and a nap on day one was too
  strict. The carrier and the menu bar now show the weekly %; today's share sets his pace (past it
  he sweats: "ahead of today's share, take it slow"), and the popover says when the week resets.
  Codex's basket follows the same rule.

### Removed
- The ink-wash style. Grandpa Yugong, and every character after him, is pixel art only: the
  style picker in the popover, the `--style` flag and the ink drawing code are gone.

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
