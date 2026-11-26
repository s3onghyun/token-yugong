# Changelog

## Unreleased

### Fixed
- Claude's limits now come from Claude Code itself: the app runs the unmodified `claude -p /usage` once per
  profile (the default `~/.claude`, plus any `CLAUDE_CONFIG_DIR` folder you add in Settings › Accounts) and
  reads only its structured rows. A status line names no account, so every release up to 0.3.8 had to guess
  which account a number belonged to, and each guess broke somewhere. 0.3.8's guess was the weekly reset time,
  which two accounts (for example two Max x20 plans) can share. Each profile's answer is that profile's login,
  so two accounts can no longer mix in one row, whatever their reset times. The app never reads a token and
  never calls an Anthropic endpoint itself.
- Asks are rare: once at start, when you open the popover (at most once per 5 minutes per profile), and every
  30 minutes ± 5 in the background (Settings › *Ask Claude Code every 30 minutes* turns that off). Activity never
  triggers one. When Claude Code answers without fresh limits (rate limited, signed out), that profile waits
  1 hour, then 2, 4 … up to a day, and the background refresh skips it until the popover is opened.
- Output the app cannot read shows "don't know", never an older number. Between asks the popover shows the
  last answer with its age.

### Changed
- The status-line bridge only prints the session's own percentage and writes no file. Connecting it is
  optional. `TokenPet status` prints the app's last `/usage` answer.
- Rows saved by 0.3.8 and older (keyed by a weekly reset or an account hash) are dropped once; rows are now
  named by the profile's signed-in email or your nickname.
- Removed: reading Claude Desktop's plan history and Claude Code's `usage_limit_reached` log lines (both were
  stand-ins for what `/usage` now reports).

### 수정
- Claude 한도를 이제 Claude Code 자신에게서 받습니다. 앱이 수정하지 않은 `claude -p /usage`를 프로필마다 한 번씩
  실행하고(기본 `~/.claude`, 그리고 설정 › 계정에서 추가한 `CLAUDE_CONFIG_DIR` 폴더) 그 구조화된 행만 읽습니다.
  상태줄에는 계정이 적혀 있지 않아 0.3.8까지는 숫자가 어느 계정의 것인지 추측해야 했고, 추측은 모두 어딘가에서
  깨졌습니다. 0.3.8은 주간 리셋 시각으로 추측했는데, 두 계정(예: Max x20 두 개)이 같은 시각일 수 있습니다. 프로필의
  답은 그 프로필 로그인의 것이라, 리셋 시각이 같아도 두 계정이 한 행에 섞이지 않습니다. 앱은 토큰을 읽지 않고
  Anthropic 엔드포인트를 직접 부르지도 않습니다.
- 드물게 묻습니다. 앱을 켤 때 한 번, 팝오버를 열 때(프로필마다 5분에 한 번까지), 백그라운드로 30분 ±5분마다
  (설정 › *30분마다 Claude Code에 묻기*로 끔). 사용 활동으로는 묻지 않습니다. Claude Code가 새 한도 없이 답하면
  (rate limit, 로그아웃) 그 프로필은 1시간, 다음엔 2·4시간 … 최대 하루 쉬고, 팝오버를 열 때까지 백그라운드에서
  묻지 않습니다.
- 읽지 못한 출력은 예전 숫자가 아니라 "모름"으로 보입니다. 묻는 사이에는 마지막 답을 그 나이와 함께 보여 줍니다.

## 0.3.8 (2026-11-26)

### Fixed
- Claude accounts are now told apart by their own limits: the moment in the week each account's
  weekly limit resets. 0.3.7 (and every release before it) guessed the account from local login
  state, which running sessions do not follow at the same time, so one account's row could still
  show another account's numbers. Saved rows move once to their reading's weekly reset, and the
  account list names each row by it ("Claude · weekly reset Wed 22:00") unless it has a nickname.
- An idle Claude Code session no longer puts its older numbers back over a newer answer: the
  status-line bridge writes a reading only when a session's limits change. The bridge no longer
  reads `~/.claude.json` or session transcripts.
- Claude 계정을 이제 한도 데이터 자체, 곧 계정마다 주간 한도가 리셋되는 요일·시각으로 구분합니다. 0.3.7까지는
  로컬 로그인 정보로 계정을 추측했는데, 실행 중인 세션들은 로그인 변경을 저마다 다른 때에 따라가므로 한 계정
  행에 다른 계정 숫자가 들어갈 수 있었습니다. 저장된 행은 한 번 각 읽기의 주간 리셋으로 옮기고, 계정 목록은
  별명이 없으면 "Claude · 주간 리셋 수 22:00"처럼 표시합니다.
- 쉬고 있는 Claude Code 세션이 예전 숫자를 새 응답 위에 다시 덮어쓰지 않습니다. 상태 줄 브리지는 세션의
  한도가 바뀔 때만 기록하고, 더는 `~/.claude.json`이나 세션 대화 기록을 읽지 않습니다.

## 0.3.7 (2026-11-26)

### Fixed
- With Claude Code sessions open on two accounts (for example after a `/login` while older sessions
  keep running), the menu bar no longer flips every 30 seconds between the two accounts' limits
  under one account. The status-line bridge now tags each reading with the account that owns that
  session (the `session-owner` record Claude Code writes into the session's transcript) instead of
  whichever account is logged in right now.
- After the popover had been opened once, its closed scene kept drawing 8 frames a second in the
  background (about 15% CPU on a busy Mac). The scene now stands still while the popover is closed.
- 두 계정으로 Claude Code 세션이 열려 있으면(예: `/login` 뒤에도 예전 세션이 계속 도는 경우) 메뉴 막대가
  한 계정 이름으로 두 계정의 한도를 30초마다 번갈아 보여 주던 문제를 고쳤습니다. 상태 줄 브리지가 지금
  로그인된 계정이 아니라 그 세션을 쓰는 계정(Claude Code가 세션 대화 기록에 남기는 `session-owner`)으로
  읽기를 구분합니다.
- 팝오버를 한 번 연 뒤에는 닫혀 있어도 장면이 뒤에서 초당 8번 계속 그려지던 문제(바쁜 Mac에서 CPU 약 15%)를
  고쳤습니다. 이제 팝오버가 닫혀 있으면 장면이 멈춰 있습니다.

## 0.3.6 (2026-11-20)

### Changed
- A Claude Code login change no longer switches Grandpa's account by itself. The first account
  that reports a reading is selected; after that the account you choose in the picker stays
  selected, including across a restart. An account choice saved by an older version is carried
  over once.
- Claude Code에서 로그인이 바뀌어도 할아버지가 저절로 계정을 바꾸지 않습니다. 처음 읽기를 보낸 계정이
  선택되고, 그다음에는 계정 목록에서 고른 계정이 다시 시작한 뒤에도 그대로 유지됩니다.
  예전 버전이 저장한 계정 선택은 한 번 옮겨 옵니다.

## 0.3.5 (2026-11-20)

### Fixed
- When the newest Claude status-line reading leaves out the 5-hour window, Grandpa no longer keeps
  an earlier 5-hour value (such as 100%) next to the newer weekly number; each reading replaces the
  previous one for that account, and an older reading read later never overwrites a newer one. The
  account picker shows how long ago each reading was taken.
- 가장 최근 Claude 상태 줄 읽기에 5시간 창이 없으면, 새 주간 사용량 옆에 예전 5시간 값(예: 100%)을 더는
  붙들지 않습니다. 계정마다 새 읽기가 이전 읽기를 통째로 대신하고, 나중에 읽힌 더 오래된 읽기는 새
  읽기를 덮어쓰지 않습니다. 계정 목록에는 각 읽기가 얼마 전에 읽혔는지 보여 줍니다.

## 0.3.4 (2026-11-18)

### Added
- **Send feedback…** (speech-bubble button in the popover, and the mini window's right-click menu)
  opens a GitHub issue, or an email to s3onghyun.hong@gmail.com, prefilled with the app version, macOS
  version and the AIs the family watches. The app sends nothing itself: nothing goes out until you
  submit it yourself, and no paths, names or work content are included.
- **의견 보내기…**(팝오버의 말풍선 버튼, 작은 창 오른쪽 클릭 메뉴)를 누르면 앱 버전, macOS 버전, 가족이
  보는 AI가 채워진 GitHub 이슈나 s3onghyun.hong@gmail.com 앞 이메일이 열립니다. 앱이 직접 보내는 것은
  없으며, 직접 제출하기 전에는 아무것도 전송되지 않고 경로·이름·작업 내용은 들어가지 않습니다.

### Security
- **Update** only installs an app signed by the same Developer ID team as the running one and notarized by
  Apple; a build you made yourself (ad-hoc signed) checks the signature as before.
- The `settings.json` backups in `~/.claude/token-pet/` are readable by you only, and only the newest three
  are kept.
- The status-line bridge runs `jq`, `date` and its other tools from the system and Homebrew folders only (a
  chained status line still gets Claude Code's `PATH`), and removes its per-session files after 30 days.
- An out-of-range time in `limits.json` or a Claude Code log is ignored instead of closing the app or
  `TokenPet status`.
- OpenAI and DeepSeek spend checks use a private session with no shared cookies or cache.
- Release builds attest the Linux AppImage and `.deb` too; CI pins every action by commit and does not
  keep the checkout token.
- **업데이트**는 지금 앱과 같은 Developer ID 팀이 서명하고 Apple 공증을 받은 앱만 설치합니다. 직접 빌드한
  앱(ad-hoc 서명)은 전처럼 서명만 확인합니다.
- `~/.claude/token-pet/`의 `settings.json` 백업은 나만 읽을 수 있고, 최근 세 개만 남깁니다.
- 상태줄 브리지는 `jq`, `date` 등 도구를 시스템·Homebrew 폴더에서만 찾고(이어 붙인 상태줄은 Claude Code의
  `PATH`를 그대로 받습니다), 세션별 파일은 30일이 지나면 지웁니다.
- `limits.json`이나 Claude Code 기록의 범위를 벗어난 시각은 무시하고, 앱이나 `TokenPet status`가 꺼지지
  않습니다.
- OpenAI·DeepSeek 지출 확인은 쿠키·캐시를 공유하지 않는 별도 세션을 씁니다.
- 릴리스는 Linux AppImage와 `.deb`에도 빌드 출처 증명을 붙이고, CI는 모든 액션을 커밋으로 고정하며
  체크아웃 토큰을 남기지 않습니다.

## 0.3.3 (2026-11-18)

### Changed
- The macOS app is Developer ID signed, notarized by Apple and stapled; the first launch no longer needs
  **Open Anyway** in System Settings. The in-app update and `brew upgrade` move to it as usual.
- macOS 앱이 Developer ID로 서명되고 Apple 공증을 받아 티켓이 붙어(staple) 나옵니다. 처음 실행할 때
  시스템 설정의 **그래도 열기**가 더는 필요 없습니다. 앱 안 업데이트와 `brew upgrade`도 평소처럼 됩니다.

## 0.3.2 (2026-11-17)

### Fixed
- After a Claude limit is reset early (its reset time unchanged), Grandpa shows the new, lower
  percentage from the next status-line reading instead of keeping the old high one until the window
  ends. A higher number saved by 0.3.1 is replaced by that reading too; an older reading read later
  never overwrites a newer one.
- Claude 한도가 예정보다 일찍 초기화되어도(초기화 시각은 그대로) 다음 상태 줄 읽기부터 새로 낮아진
  사용량을 보여 줍니다. 창이 끝날 때까지 예전의 높은 값을 붙들지 않으며, 0.3.1이 저장해 둔 높은 값도
  그 읽기로 바로잡힙니다. 나중에 읽힌 더 오래된 읽기는 새 읽기를 덮어쓰지 않습니다.

## 0.3.1 (2026-11-12)

### Fixed
- After a Claude Code login change, Grandpa follows the newly signed-in account. Choosing another
  account in the picker stays in effect until the next login change.
- Claude Code에서 로그인 계정이 바뀌면 할아버지가 새로 로그인한 계정을 바로 봅니다. 계정 목록에서
  다른 계정을 고르면 다음 로그인 변경 전까지 그 선택을 유지합니다.

## 0.3.0 (2026-11-12)

### Changed
- Claude readings are saved separately for each account. Choose the account Grandpa watches from the
  account list; old accounts stay there until you remove them.
- Claude 계정별 읽기를 따로 저장합니다. 계정 목록에서 할아버지가 볼 계정을 고를 수 있고,
  예전 계정은 직접 지울 때까지 목록에 남아 있습니다.

### Fixed
- Switching Claude accounts while sessions are still open now finds the new account's next response.
  An unchanged redraw from before the switch is ignored instead of keeping the old account forever.
- Claude 계정을 바꾼 뒤에도 열려 있던 세션이 새 계정의 다음 응답을 가로막지 않습니다.
  전환 전과 같은 다시 그리기는 무시하고, 예전 계정에 계속 묶어 두지 않습니다.

## 0.2.10 (2026-11-10)

### Fixed
- Claude Max accounts now recover a freshly reported 5-hour percentage from Claude Desktop's local
  plan history when the Claude Code status line omits `five_hour`. The status line still supplies
  account identity and reset times; an absent or stale 5-hour value clearly falls back to the weekly limit.
- After a Claude Code account switch, a still-running session's old named status-line payload is ignored.
  Yugong clears the prior account's numbers and waits for a response from the newly signed-in account.

## 0.2.9 (2026-11-08)

### Added
- Linux desktop beta releases now include an x86_64 AppImage and `.deb`, each with a SHA-256 checksum.
  The Windows desktop beta remains a CI artifact while the project seeks OSS code signing.

## 0.2.8 (2026-11-07)

### Changed
- The Homebrew upgrade command's Copy button now briefly becomes **Copied** / **복사됨** with a checkmark, and announces the successful copy to VoiceOver.

## 0.2.7 (2026-11-07)

### Fixed
- Low Power Mode now holds a forward-facing idle pose, retaining the blue jacket and red sash instead of looking washed out in the menu bar.
- Local usage scans now wake after a watched bridge or usage directory changes, coalesced and throttled to one scan per 30 seconds. The old 20-second polling loop is a five-minute recovery check instead, so an otherwise static menu-bar pet does not spend CPU scanning unchanged files.

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
