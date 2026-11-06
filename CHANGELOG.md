# Changelog

## 0.2.6 (2026-11-07)

### Changed
- Menu-bar animation now holds a static pose in Low Power Mode and avoids preparing sprite frames at all when the pet image is off. Static percentage labels refresh at most every five minutes; countdown labels refresh once a minute. The existing one-shot, tolerant timer continues to stop for an asleep display, locked/inactive session, or an occluded/hidden status item.
- The animated menu-bar item now keeps a fixed width and swaps cached sprites through a compositor layer rather than AppKit's image cell. This avoids AppKit's menu-bar layout pass on every frame; the optional SwiftUI recording stage is no longer published to while closed, and text still changes only when its value changes.
- AppKit gives one `NSStatusItem` one shared image, replicated by the system on every menu bar; it does not expose a per-display image or the display a copied item is being viewed on. Yugong therefore cannot animate only the active copy. It uses one cached image and skips all redraws when its item is not visible instead.

### Fixed
- A Claude Code status-line update can report only the weekly window immediately after the 5-hour reset. Yugong now keeps that valid reading even if an older account switch left no current reading, explicitly shows the 5-hour reset as unknown, and continues to show the weekly limit.

## 0.2.5 (2026-11-06)

### Added
- The popover shows the masked signed-in Claude account and explains when the displayed limits belong to the previous account.
- **Check now** re-reads Claude's local account and usage files without making a network request.

## 0.2.4 (2026-11-05)

### Fixed
- After a Claude Code `/login`, an already-running session could redraw its old account's limits.
  The bridge had been reading the *current* global login for every redraw and consequently relabelled
  that old payload as the new account. It now pins each status-line session to the first account hash
  it sees, so alternating old/new sessions stay separated and Yugong can ignore the old reading. Both
  the account and session identifiers are SHA-256 hashes kept only on this Mac; no raw identifier,
  prompt, path or telemetry is saved.
- When an old session is the first to redraw after the switch, the popover now says **계정 바뀜 감지**
  and waits for a reply from the new account instead of calling the old payload the new account's usage.
- If Claude Code omits `five_hour`, Yugong now says it is showing the weekly limit because the 5-hour
  window is not being reported *right now*, rather than claiming the account has no 5-hour limit.

## 0.2.3 (2026-11-05)

### Added
- **Update** in the new-version row: downloads that release's ZIP, checks it (size, same bundle id,
  exactly that version, `codesign --verify`), swaps it in for the running app and restarts. On any
  failure the current app is left as it was. Installed with Homebrew, the row shows
  `brew upgrade --cask s3onghyun/tap/token-yugong` with a Copy button instead; where the app cannot be
  replaced, it points to the release page.

### Fixed
- The popover opened from the mini window could be cut off at the bottom of a shorter screen (with
  Settings or More open it grew past the screen). It now stays within the screen and scrolls.

## 0.2.2 (2026-11-04)

### Added
- Homebrew: `brew install --cask s3onghyun/tap/token-yugong` (from the
  [s3onghyun/homebrew-tap](https://github.com/s3onghyun/homebrew-tap) tap, bumped to each new release).
- *Compact* in the Yugong window's ⋯ menu (and right-click): only the scene and its headline, for a
  small window on the desktop. Remembered; unticking it brings the meters and actions back.
- One-click and one-command Claude Code setup. **Connect** in the guide shows the `statusLine`
  before and after and writes it into `~/.claude/settings.json` only when you agree;
  `TokenPet setup` (in `TokenYugong.app/Contents/MacOS/`) does the same from a terminal or an agent,
  `--dry-run` only shows it, `--undo` (or **Undo** in the guide) puts it back. Only the `statusLine`
  member changes, every other byte of the file stays, a backup goes next to `limits.json`, running it
  twice changes nothing, and a symlinked settings file stays a link. A status line you already have is
  kept: the bridge's new `--chain '<command>'` passes it the same input and shows its output. Without
  Claude Code (no `~/.claude`) it says so and writes nothing.
- A command line for agents: `TokenPet status --json` (connected or not, the last limits) and
  `TokenPet setup --json`, with stable keys, plain-language errors on stderr and exit code 1.

### Changed
- Japanese and Chinese wording: one word for each thing across the app (Japanese リミット, not
  sometimes 上限; Chinese 额度, 背架 and token, not sometimes 限额, 背篓 or 令牌), full-width
  punctuation in the titles window, and a few stiff lines rewritten (*limit has reset* is リセット, not
  戻った).
- The first-run guide takes about 30 seconds: what Grandpa shows (the carrier, his pace, the mountain)
  on one page, **Connect** for Claude Code, then where Settings and the Yugong window's ⋯ menu are.
  **Skip** on every page; it still shows once by itself and Settings › *How it works and Claude Code
  setup…* opens it again.
- The popover is compact again, close to the first releases (about 510 points tall instead of 650 with
  the 5-hour and weekly meters and one more AI): the scene, the state and headline, the mountain,
  every meter and the pace, any update or account-change notice, and one row of actions. The ⌄
  button next to Refresh (*더 보기*) shows the rest: the title and its ladder (click for all titles),
  where the numbers come from, the Claude account line, the shovel speed, the screen-sharing toggle,
  the weekly-only explanation and the other AIs' source notes. It stays open or closed as you left it,
  in the popover and the Yugong window alike. Without any Claude limits yet, the note on how to
  connect the status line stays in view.

### Fixed
- Overnight, once the 5-hour window had reset, Yugong took the Claude account for one with only a
  weekly limit (*No 5-hour limit on this account*), the same note it had shown for the other account
  the evening before, and the wife came to ask about a change of plan, at the reset and again when
  the window came back. Claude Code drops a window from the status line once it resets; a window
  that has reset now stays as a new, empty one (0%) until the next reading fills it.
- Accounts are told apart by name, not only by guess. Correction to the fix below: the "weekly-only"
  numbers seen after the `/login` were the *old* account's, from idle sessions (its 5-hour window had
  reset and was dropped), and running sessions do follow the new login; they only keep the numbers of
  their last answer until they answer again. The bridge now adds a 12-character SHA-256 hash of the
  signed-in account's id (`oauthAccount.accountUuid` in `.claude.json`; the id itself is never
  stored), so the account in use is known, and an idle session's numbers of another account are
  ignored however long the current one has been quiet (the 30-minute rule let them take the app back
  overnight). Bridges that name no account keep the weekly-reset rules. An installed bridge older
  than the app is replaced at launch; `settings.json` is not touched.

### Added
- The popover (behind ⌄ since the compact popover) names the Claude account and when its numbers came:
  *Claude 계정 A · 8edcde · 마지막 갱신 09:24* (accounts lettered in the order first seen, with the
  first 6 characters of the hash).
- `~/Library/Application Support/TokenPet/claude-readings.log`: every bridge reading the app took or
  ignored, with the hashed account and what it showed (at most two files of 512 KB), so a mix-up can
  be traced afterwards.
- After switching the Claude account (`/login`), Yugong kept showing the old account. Claude Code
  sessions started before the switch keep the old account, keep writing its numbers into the one
  bridge file and keep logging its refused requests, so the old 5-hour window, its 99% and its rest
  came back over the new account's numbers. The status line carries no account, so the app now tells
  accounts apart by their weekly reset time: on a new one it switches, says *Account change
  detected* (계정 바뀜 감지) in the popover, and ignores the old account's readings and limit hits
  while the new one is in use (30 minutes of silence from it lets the old one back, for a switch
  back). An account with only a weekly window no longer picks up the old account's 5-hour limit.
  Sessions of one account are merged, so an idle session no longer drops the 5-hour window or brings
  back an older percent. Only reset times and percentages are kept, on this Mac.

## 0.2.1 (2026-11-03)

### Changed
- One public name: **Token Yugong**. The app is now `TokenYugong.app` (shown as *Token Yugong*), the
  release archive `TokenYugong-<version>-macos-universal.zip`, and the update check says
  `User-Agent: TokenYugong/<version>`. The executable, the bundle identifier and the `TokenPet`
  settings domain stay, so settings, the mountain and titles carry over: quit Yugong Pet, delete
  `YugongPet.app`, and if *Open at login* was on, turn it off and on once.
- The first-launch steps follow macOS 15 and later: System Settings › Privacy & Security › *Open
  Anyway* first; Control-click › Open is the macOS 13-14 alternative.
- `LICENSE` is the plain MIT text, so GitHub reads it as MIT; which files it covers (and that
  `assets/` is not among them) is stated in the README and `assets/LICENSE.md`. The character art is
  final, no longer a prototype.
- README: a short top with the install line, badges and a new animation drawn by the app's own code
  (`YugongSheet --hero`: digging, nearly full, the nap while Zhisou laughs, the reset, a new title),
  a Privacy section listing everything the app reads and every network request, and full Japanese and
  Simplified Chinese READMEs (AI-assisted translations; corrections welcome). `YugongSheet --social`
  draws the 1280x640 link preview. CONTRIBUTING.md and issue templates for bugs and translations.
- The mini window (shown when the menu bar has no room) draws Grandpa at twice the bar size, pixel for
  pixel, with a larger number, so it no longer reads as a lone number, and hovering says *Click to see
  Grandpa Yugong* (눌러서 우공 보기). An older, smaller saved mini window grows to the new size in place.
- The scene's shovel blade is drawn without its inner outline, so its colour (wood, iron, gold) reads.

### Fixed
- Grandpa never rested when a Claude limit was used up: the meter stayed at 99% and he kept digging.
  Claude Code's status line reports the last successful response, and the request that would reach
  100% is refused, so 100% never arrived (sometimes the 5-hour window vanished instead). The app now
  also reads the refusal Claude Code logs (`usage_limit_reached`, with the window and its reset time):
  the meter shows 100%, he sits down to rest, Zhisou comes to gloat, and the menu bar counts down to
  the reset. If Claude answers again (another account, extra usage) the refusal no longer counts.
  A percentage rounds up to 100% only when the window is really full (99.5 reads 99%).
- Clicking Grandpa in the menu bar opened the popover on another display (or under the mini window)
  instead of under the icon you clicked. macOS 26 draws menu-bar items as Control Center copies on
  every display, while the app's own item window stays on one display or parked off-screen, and the
  popover was anchored to that window. A click in a menu bar now opens it right there.

### Added
- When Grandpa's limit is used up: one notification with the reset time, and one when it resets
  (Settings › *Notify when the limit is used up and when it resets*, on by default). The popover counts
  down ("쉬는 중 · 2시간 3분 뒤 다시 퍼요"), the source line says how old the reading is, and a used-up
  weekly limit rests under a full moon.
- Title rewards: every title now adds one thing to the scene, automatically, and it stays. Before the
  first title the shovel is wooden; then the iron blade (#1), a teal tassel on the carrier (#2), a
  pickaxe and broken stones (#3), two baskets (#4), the Bohai Sea with an islet of dumped earth (#5),
  terraced fields on the carved slope (#6), the family's thatched house (#7), the family banner (#8),
  auspicious clouds (#9), and a golden shovel with an open road and a milestone (#10). #1, #2, #3, #8
  and #10 show in the menu bar too; Grandpa's face, hat and clothes never change. Props step aside
  for whoever stands in the scene, a new reward twinkles while the magpie announces it, and the title
  card shows them. Settings › *Hide background props* (배경 소품 숨기기) keeps only Grandpa's gear.
- The finale: after the top title's celebration, once, Kua'e's two sons carry both mountains off, one
  east and one south, and leave the open road. *Watch the finale again* in the titles window replays it
  in the Yugong window; `--demo finale` shows it in a demo. `YugongSheet <dir> --rewards` renders every
  title before and after for review.
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
