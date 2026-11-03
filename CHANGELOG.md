# Changelog

## Unreleased

### Added
- The Yugong window: the popover's **Window** button (창으로 보기) opens the scene, the mountain, the
  title and every meter in a window of its own. Drag it to any display, resize it (the content scales),
  or pick small, medium or large, a normal window, always on top or on the desktop, and the opacity
  from its ⋯ button or a right-click. Esc closes it. Size, place, level and opacity are remembered,
  and a window whose display is gone comes back on the main screen. Settings › *Open the Yugong
  window when the app starts* (off by default). It draws nothing while closed or covered.
- Finding Grandpa: the first-run guide says to click him in the menu bar, and a one-time hint under
  the bar item says so too (shown once, also to existing users; skipped once the popover was opened).
  Opening the app again with no room in the bar and the mini window off now opens the Yugong window,
  and the mini window's right-click menu can open it. `--window` opens it in a demo.
- Japanese (日本語) and Simplified Chinese (简体中文) alongside English and Korean: Settings › Language
  is System, English, 한국어, 日本語 or 简体中文, and a change shows at once without a restart (the guide
  window title, the mini window and the menu-bar clock follow too). System picks the first of your
  preferred languages the app has (Traditional Chinese falls through to the next one, not Simplified).
  Clock text and token counts use that language's format (月 04:00, 周一 04:00, 12万, 2.5亿). The app
  bundle declares its languages, so System Settings › Language & Region › Applications can pin one.
- Update notice: at most once a day the app asks GitHub for the latest release (one HTTPS GET, fixed
  headers, no cookies, no telemetry). A newer version shows a popover row with *Release page* and
  *Skip this version*, plus one notification per version. Settings › *Check for updates (once a day)*
  turns it off and *Check now* asks at once. The app never downloads or installs anything itself.
- `--lang pseudo`: every string about 40% longer and accented, for finding truncation with `--render`.
- Tests: every `L.t` call in the sources must carry a non-empty translation in the right script, with the
  same values as the English; Korean-only strings outside `L.t` fail; version order, the daily throttle
  and the release parsing are covered.
- Titles: ten ranks earned by every token carried (all mountains together), from 삽 든 손주
  (100k, the first session) to 산을 옮긴 우공 (3B, months), shown with the progress to the next in
  the popover; five achievements (full carrier, 7-day streak, a week kept under the limit, two AIs
  on one day, up for a dawn reset). A promotion brings pixel confetti and the magpie's announcement
  and one notification. The titles window (click the title row) lists earned and locked ones and
  saves a title card as PNG: the pixel scene and totals, no personal data, nothing sent.
  Rules and the curve in LOGIC.md › Titles. Demo flags: `--lifetime`, `--award`, `--titles`.

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
