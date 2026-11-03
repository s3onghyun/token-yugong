import SwiftUI
import TokenPetAssets

enum Fmt {
    static func clock(_ d: Date, now: Date = Date(), tz: TimeZone = .current, lang: Lang = L.lang) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let f = DateFormatter()
        f.locale = lang.locale; f.timeZone = tz
        f.dateFormat = cal.isDate(d, inSameDayAs: now) ? "HH:mm" : (lang == .en ? "EEE HH:mm" : "E HH:mm")
        return f.string(from: d)
    }
    static func until(_ d: Date, now: Date = Date()) -> String {
        let m = max(0, Int(d.timeIntervalSince(now) / 60))
        if m >= 24 * 60 { return L.t("in \(m / 1440)d \((m % 1440) / 60)h",
                                     "\(m / 1440)일 \((m % 1440) / 60)시간 뒤",
                                     "\(m / 1440)日\((m % 1440) / 60)時間後",
                                     "\(m / 1440)天\((m % 1440) / 60)小时后") }
        if m >= 60 { return L.t("in \(m / 60)h \(m % 60)m",
                                "\(m / 60)시간 \(m % 60)분 뒤",
                                "\(m / 60)時間\(m % 60)分後",
                                "\(m / 60)小时\(m % 60)分钟后") }
        return L.t("in \(m)m", "\(m)분 뒤", "\(m)分後", "\(m)分钟后")
    }
    /// "3m ago", "2h 5m ago": how old a reading is.
    static func ago(_ d: Date, now: Date = Date()) -> String {
        let m = max(0, Int(now.timeIntervalSince(d) / 60))
        if m >= 60 { return L.t("\(m / 60)h \(m % 60)m ago", "\(m / 60)시간 \(m % 60)분 전", "\(m / 60)時間\(m % 60)分前", "\(m / 60)小时\(m % 60)分钟前") }
        return L.t("\(m)m ago", "\(m)분 전", "\(m)分前", "\(m)分钟前")
    }
    /// A percent used: 100% only when the window is really full, so 99.5 reads 99% and never "100% but still digging".
    static func pct(_ p: Double) -> String { p >= 100 ? "100%" : "\(min(99, Int(p.rounded())))%" }
    /// Compact time left for the menu bar: "5d 2h", "3h 12m", "12m".
    static func left(_ d: Date, now: Date = Date()) -> String {
        let m = max(0, Int(d.timeIntervalSince(now) / 60))
        if m >= 24 * 60 { return "\(m / 1440)d \((m % 1440) / 60)h" }
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return "\(m)m"
    }
    static func tokens(_ n: Int, lang: Lang = L.lang) -> String {
        if lang != .en {   // East Asian units: 만/억, 万/億, 万/亿
            let (man, oku) = [Lang.ko: ("만", "억"), .ja: ("万", "億"), .zh: ("万", "亿")][lang]!
            if n >= 100_000_000 { return String(format: "%.1f", Double(n) / 1e8) + oku }
            if n >= 10_000 { return "\(n / 10_000)" + man }
            return "\(n)"
        }
        return n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? "\(n / 1000)k" : "\(n)"
    }
}

struct PopoverView: View {
    @ObservedObject var model: UsageModel
    var fixedT: TimeInterval? = nil  // set when rendering stills
    var now: Date? = nil
    var cutsceneT: Double? = nil     // stills: freeze the cutscene at this progress
    var inWindow = false             // shown in the Yugong window (SceneWindow), not the popover

    static let sceneSize = CGSize(width: 292, height: 176)
    @State var showSettings = args.contains("--settings")   // demo: open with settings shown

    var body: some View {
        let s = model.snap
        VStack(alignment: .leading, spacing: 10) {
            scene(s)
            HStack(alignment: .firstTextBaseline) {
                Text(model.cutsceneDue ? L.t("The mountain is moving!", "산이 옮겨져요!", "山が動いていく！", "山在移动！")
                     : model.finaleDue ? L.t("The mountains are moving!", "두 산이 옮겨져요!", "二つの山が動いていく！", "两座山在移动！") : stateTitle(s.state))
                    .font(.system(.headline, design: .rounded))
                Spacer()
                if let d = BarText.detail(s, now: clockNow) {
                    Text(d).font(.subheadline.monospacedDigit().weight(.semibold)).foregroundColor(.secondary)
                }
            }
            mountainRow
            Button { model.openTitles?() } label: { TitleProgress(lifetime: model.lifetime).contentShape(Rectangle()) }
                .buttonStyle(.plain).help(L.t("All titles and achievements…", "칭호와 업적 모두 보기…", "称号と実績をすべて見る…", "查看全部称号与成就…"))
            let main = model.family.roles[.grandpa] ?? .claude
            Text("\(main.name) · \(Role.grandpa.name) \(Role.grandpa.meter)").font(.caption.weight(.bold)).foregroundColor(.secondary)
            if !s.known {
                meterRow(L.t("Limit", "한도", "リミット", "额度"), nil)
            } else if let d = s.daily {
                // no 5-hour window on this account: the weekly limit is the carrier, today's share only sets the pace
                meterRow(L.t("Weekly (the carrier)", "주간 (지게)", "週間（背負子）", "每周（背架）"), s.week)
                meterRow(L.t("Today's share: pace (1/7 of the week)",
                             "오늘 몫: 속도 (주간의 1/7)",
                             "今日の取り分：ペース（週の1/7）",
                             "今日份额：节奏（每周的 1/7）"), Meter(pct: d.fill * 100, resetsAt: d.dayEnd), pace: true)
                Text(L.t("No 5-hour limit on this account, only weekly. Grandpa naps only when the weekly limit runs out\(weeklyReset(s)); going past today's share just makes him sweat.",
                         "이 계정은 5시간 한도 없이 주간 한도만 있어요. 할아버지는 주간 한도를 다 쓸 때만 쉬어요\(weeklyReset(s)). 오늘 몫을 넘으면 땀만 흘려요.",
                         "このアカウントには5時間リミットがなく、週間リミットだけです。おじいさんが休むのは週間リミットを使い切ったときだけです\(weeklyReset(s))。今日の取り分を超えても汗をかくだけです。",
                         "这个账号没有 5 小时额度，只有每周额度。只有每周额度用完时爷爷才会打盹\(weeklyReset(s))；超过今日份额只会让他流汗。"))
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                windowRows(Reading(five: s.five, week: s.week, at: s.captured ?? clockNow, month: s.month))
            }
            if let p = s.projected, s.known, s.state != .resting, s.daily == nil {
                Text(L.t("At this pace: about \(Int(p.rounded()))% by the reset",
                         "이 속도면 리셋 때 약 \(Int(p.rounded()))%",
                         "このペースだとリセット時に約\(Int(p.rounded()))%",
                         "按这个速度，重置时约为 \(Int(p.rounded()))%"))
                    .font(.caption).foregroundColor(p >= 100 ? Color(red: 0.8, green: 0.3, blue: 0.2) : .secondary)
            }
            note(s.demo ? L.t("Simulated state for preview.",
                              "미리보기용 가상 상태입니다.",
                              "プレビュー用の仮の状態です。",
                              "预览用的模拟状态。") : source(main, s.known ? s.captured : nil))
            if !s.demo {
                Text(L.t("Shovel speed: \(Int(model.pace.smoothed.rounded())) output tokens/min (last 3 min, this Mac)",
                         "삽질 속도: 분당 출력 토큰 \(Int(model.pace.smoothed.rounded())) (최근 3분, 이 Mac)",
                         "掘る速さ：毎分 \(Int(model.pace.smoothed.rounded())) 出力トークン（直近3分、この Mac）",
                         "挖土速度：每分钟 \(Int(model.pace.smoothed.rounded())) 个输出 token（最近 3 分钟，本机）"))
                    .font(.caption).foregroundColor(.secondary)
            }
            ForEach([Role.son, .grandson, .boy].filter { model.family.roles[$0] != nil }) { role in
                // one row each: his headline window (5-hour, else weekly, else the month's budget)
                let p = model.family.roles[role]!, r = s.members[role]?.reading
                Divider()
                meterRow("\(p.name) · \(role.name) \(role.meter)", r.flatMap { $0.five ?? $0.week ?? $0.month })
                if r == nil || s.demo == false && p.billed { note(source(p, r?.at)) }
            }
            if let v = model.updateOffer { updateRow(v) }
            Button { model.hideFromCapture.toggle() } label: {
                HStack(spacing: 6) {
                    let hidden = model.hideFromCapture && !model.captureAllowedForDemo
                    Image(systemName: hidden ? "eye.slash.fill" : "eye")
                    Text(model.captureAllowedForDemo ? L.t("Capture allowed for this demo recording",
                                                           "데모 녹화를 위해 잠시 캡처 허용",
                                                           "デモ録画のため一時的にキャプチャを許可",
                                                           "为录制演示暂时允许截屏")
                         : hidden ? L.t("Hidden from screen sharing", "화면 공유·녹화에서 숨김", "画面共有・録画で非表示", "在屏幕共享和录制中隐藏")
                                  : L.t("Visible in screen sharing", "화면 공유·녹화에 보임", "画面共有・録画で表示", "在屏幕共享和录制中可见"))
                }
                .font(.caption)
            }
            .buttonStyle(.plain).foregroundColor(.secondary)
            if showSettings { settings }
            HStack {
                Button { showSettings.toggle() } label: { Image(systemName: showSettings ? "gearshape.fill" : "gearshape") }
                    .buttonStyle(.plain).foregroundColor(.secondary).help(L.t("Settings", "설정", "設定", "设置"))
                if !inWindow {
                    Button { model.openWindow?() } label: { Label(L.t("Window", "창으로 보기", "ウィンドウ", "窗口"), systemImage: "macwindow") }
                        .buttonStyle(.plain).foregroundColor(.accentColor).fixedSize()
                        .help(L.t("Show Grandpa in a window of his own: resize it, keep it on top or on the desktop",
                                  "할아버지를 따로 창으로 띄워요. 크기를 바꾸고, 항상 위나 바탕화면에 둘 수 있어요",
                                  "おじいさんを別のウィンドウで表示します。大きさを変えたり、常に手前やデスクトップに置けます",
                                  "在单独的窗口中显示爷爷：可以调整大小、置顶或放在桌面上"))
                }
                if model.demo != nil || model.demoCycle || model.demoCutscene {
                    Text(L.t("Demo data", "데모 데이터", "デモデータ", "演示数据")).font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                }
                Spacer()
                Button(L.t("Refresh", "새로고침", "更新", "刷新")) { model.refresh() }.disabled(model.scanning)
                Button(L.t("Quit", "종료", "終了", "退出")) { NSApp.terminate(nil) }
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 320)
    }

    private var clockNow: Date { now ?? Date() }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(L.t("Settings", "설정", "設定", "设置")).font(.caption.weight(.bold)).foregroundColor(.secondary)
            Picker(L.t("Language", "언어", "言語", "语言"), selection: $model.language) {
                Text(L.t("System", "시스템", "システム", "跟随系统")).tag("auto")
                Text("English").tag("en")
                Text("한국어").tag("ko")
                Text("日本語").tag("ja")
                Text("简体中文").tag("zh")
            }
            Toggle(L.t("Grandpa in the menu bar", "메뉴바에 할아버지", "メニューバーにおじいさん", "菜单栏显示爷爷"), isOn: $model.barGrandpa)
            Picker(L.t("Menu bar number", "메뉴바 숫자", "メニューバーの数字", "菜单栏数字"), selection: $model.barText) {
                Text(L.t("Percent used (24%)", "사용한 % (24%)", "使用率（24%）", "已用百分比（24%）")).tag(BarText.percent)
                Text(L.t("Time to reset (3h 12m)", "리셋까지 (3h 12m)", "リセットまで（3h 12m）", "距重置（3h 12m）")).tag(BarText.timeLeft)
                Text(L.t("Reset time (Mon 04:00)", "리셋 시각 (월 04:00)", "リセット時刻（月 04:00）", "重置时间（周一 04:00）")).tag(BarText.resetClock)
                Text(L.t("None", "없음", "なし", "无")).tag(BarText.none)
            }
            Picker(L.t("Mini window", "작은 창", "ミニウィンドウ", "小窗口"), selection: $model.miniMode) {
                Text(L.t("When the menu bar is full", "메뉴바가 꽉 찼을 때", "メニューバーがいっぱいのとき", "菜单栏满时")).tag(MiniMode.auto)
                Text(L.t("Always", "항상", "常に", "始终")).tag(MiniMode.always)
                Text(L.t("Never", "끔", "表示しない", "从不")).tag(MiniMode.off)
            }
            familySettings
            Toggle(L.t("Notify when the limit is used up and when it resets",
                       "한도가 다 찼을 때와 다시 풀릴 때 알림",
                       "リミットに達したときと戻ったときに通知",
                       "额度用完和重置时通知"), isOn: $model.notifyLimits)
            let login = model.launchAtLogin
            Toggle(L.t("Open at login",
                       "로그인할 때 열기",
                       "ログイン時に開く",
                       "登录时打开"), isOn: Binding(get: { login == .enabled || login == .requiresApproval },
                                                                       set: { model.setLaunchAtLogin($0) }))
                .disabled(!model.canLaunchAtLogin)
                .help(model.canLaunchAtLogin ? "" : L.t("Only in the app bundle (scripts/bundle.sh)",
                                                        "앱 번들에서만 (scripts/bundle.sh)",
                                                        "アプリバンドルでのみ（scripts/bundle.sh）",
                                                        "仅限应用包（scripts/bundle.sh）"))
            Toggle(L.t("Hide background props", "배경 소품 숨기기", "背景の小物を隠す", "隐藏背景小物件"), isOn: $model.hideProps)
                .help(L.t("The title rewards in the sky, on the horizon and on the ground. Grandpa's own gear stays.",
                          "칭호로 생긴 하늘·지평선·땅의 소품을 감춰요. 할아버지의 연장은 그대로예요.",
                          "称号でもらった空・地平線・地面の小物を隠します。おじいさんの道具はそのままです。",
                          "隐藏称号带来的天空、地平线和地面上的小物件。爷爷自己的工具不变。"))
            Toggle(L.t("Open the Yugong window when the app starts",
                       "앱이 열릴 때 우공 창도 열기",
                       "アプリ起動時に愚公ウィンドウも開く",
                       "应用启动时同时打开愚公窗口"), isOn: $model.windowAtLaunch)
            if login == .requiresApproval {
                Text(L.t("Allow it in System Settings › General › Login Items.",
                         "시스템 설정 › 일반 › 로그인 항목에서 허용해 주세요.",
                         "システム設定 › 一般 › ログイン項目で許可してください。",
                         "请在 系统设置 › 通用 › 登录项 中允许。"))
                    .font(.caption).foregroundColor(.secondary)
            }
            HStack {
                Toggle(L.t("Check for updates (once a day)", "새 버전 확인 (하루 한 번)", "アップデートを確認（1日1回）", "检查更新（每天一次）"),
                       isOn: $model.checkUpdates)
                Spacer()
                Button(L.t("Check now", "지금 확인", "今すぐ確認", "立即检查")) { model.checkForUpdate(asked: true) }
                    .disabled(!model.checkUpdates || model.appVersion == nil || model.updateStatus == .checking)
            }
            if let line = updateStatusLine { Text(line).font(.caption).foregroundColor(.secondary) }
            Button(L.t("How it works and Claude Code setup…",
                       "사용법과 Claude Code 연결…",
                       "使い方と Claude Code の接続…",
                       "使用说明与 Claude Code 连接…")) { model.openGuide?() }
                .buttonStyle(.link)
        }
        .font(.callout)
    }

    /// The update notice: shown until the user updates or skips this version.
    private func updateRow(_ v: SemVer) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.circle.fill").foregroundColor(Color(red: 0.75, green: 0.28, blue: 0.23))
            Text(L.t("Version \(v) is out", "새 버전 \(v)", "新バージョン \(v)", "新版本 \(v)")).font(.caption.weight(.semibold))
            Spacer()
            Button(L.t("Release page", "릴리스 페이지", "リリースページ", "发布页面")) { NSWorkspace.shared.open(Update.page(v)) }
                .buttonStyle(.link)
            Button(L.t("Skip this version", "이 버전 건너뛰기", "このバージョンをスキップ", "跳过此版本")) { model.skippedVersion = v.description }
                .buttonStyle(.link).foregroundColor(.secondary)
        }
        .font(.caption)
    }

    /// Settings: this version and what the last check found.
    private var updateStatusLine: String? {
        guard let current = model.appVersion else {
            return L.t("Update checks need the app bundle (scripts/bundle.sh)", "새 버전 확인은 앱 번들에서만 (scripts/bundle.sh)",
                       "アップデート確認はアプリバンドルでのみ（scripts/bundle.sh）", "检查更新仅限应用包（scripts/bundle.sh）")
        }
        switch model.updateStatus {
        case .checking: return L.t("Token Yugong \(current) · checking…", "Token Yugong \(current) · 확인하는 중…", "Token Yugong \(current)・確認中…", "Token Yugong \(current) · 正在检查…")
        case .failed: return L.t("Token Yugong \(current) · couldn't reach GitHub", "Token Yugong \(current) · GitHub에 연결하지 못했어요",
                                 "Token Yugong \(current)・GitHub に接続できませんでした", "Token Yugong \(current) · 无法连接 GitHub")
        case .upToDate where !(model.latestVersion.flatMap(SemVer.init).map { current < $0 } ?? false):   // not when a newer one was skipped
            return L.t("Token Yugong \(current) · up to date", "Token Yugong \(current) · 최신 버전이에요", "Token Yugong \(current)・最新です", "Token Yugong \(current) · 已是最新版本")
        default: return "Token Yugong \(current)"
        }
    }

    private func info(_ s: Snapshot, t: Double) -> SceneInfo {
        func fill(_ r: Role) -> Double? { model.family.roles[r] == nil ? nil : s.members[r]?.fill ?? 0 }   // assigned but unknown: an empty meter
        var i = SceneInfo(state: s.state, carrier: s.carrier, mountainLeft: model.mountainLeft, grandson: fill(.grandson),
                          night: s.state == .resting || model.night,
                          cutscene: playing ? (cutsceneT ?? model.cutsceneStart.map { min(1, Date().timeIntervalSince($0) / 4.5) }
                                                         ?? (t / 7).truncatingRemainder(dividingBy: 1)) : nil)
        i.tempo = model.tempo
        i.son = fill(.son); i.boy = fill(.boy)
        i.visitor = model.visitor
        i.titles = model.rewards
        i.props = !model.hideProps
        i.finale = !model.cutsceneDue && model.finaleDue
        i.longRest = s.resting && (s.week?.pct ?? 0) >= 100
        if !playing, case .rank(let r)? = model.awards.first { i.sparkle = r + 1 }   // the new reward glints while the magpie tells
        return i
    }

    /// A cutscene is on: a mountain milestone or the #10 finale.
    private var playing: Bool { model.cutsceneDue || model.finaleDue }

    @ViewBuilder private func scene(_ s: Snapshot) -> some View {
        let night = !playing && (s.state == .resting || model.night)   // the cutscene sky is always golden
        let award = playing ? nil : model.awards.first   // the cutscene comes first
        let visit = award == nil ? model.visitor.map(Visitors.lines) : nil
        ZStack(alignment: .topTrailing) {
            Group {
                if let t = fixedT {
                    sceneImage(s, t: t)
                } else {
                    // SwiftUI pauses this while the popover is closed, so it costs nothing then.
                    TimelineView(.animation(minimumInterval: 1.0 / 8)) { ctx in
                        sceneImage(s, t: model.phase(at: ctx.date.timeIntervalSinceReferenceDate))
                    }
                }
            }
            if let award { celebration(award, night: night) }
            if let visit {
                // the visitor's bubble over her (his) head at the left; Grandpa answers in his
                bubble(visit.0, size: 11, night: night)
                    .frame(maxWidth: 108, alignment: .leading)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if award == nil {   // during a celebration the magpie has the floor
                bubble(model.cutsceneDue ? cutsceneLine : model.finaleDue ? finaleLine : visit?.1 ?? speech(s), size: playing || visit != nil ? 12 : 13, night: night)
                    .frame(maxWidth: playing ? 250 : visit != nil ? 158 : 150, alignment: .trailing)   // the cutscene line stays above his head
                    .padding(10)
            }
            if playing {
                Button { model.cutsceneDue ? model.finishCutscene() : model.finishFinale() } label: {
                    Text(model.cutsceneDue ? L.t("On to the next mountain", "다음 산으로", "次の山へ", "去下一座山")
                                           : L.t("Walk the open road", "탁 트인 길로", "開けた道へ", "走上大路"))
                        .font(.caption.weight(.bold)).foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(red: 0.75, green: 0.28, blue: 0.23)))
                }
                .buttonStyle(.plain)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(width: Self.sceneSize.width, height: Self.sceneSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// A new title: confetti over the scene, the magpie at the top left with the news, and a button to say thanks.
    @ViewBuilder private func celebration(_ a: Award, night: Bool) -> some View {
        Group {
            if let t = fixedT {
                Image(nsImage: TokenPetAssets.confetti(t: t, size: Self.sceneSize)).interpolation(.none)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 8, paused: Motion.reduce)) { ctx in
                    Image(nsImage: TokenPetAssets.confetti(t: ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600),
                                                           size: Self.sceneSize)).interpolation(.none)
                }
            }
        }
        .allowsHitTesting(false)
        HStack(alignment: .top, spacing: 4) {
            Image(nsImage: TokenPetAssets.magpie(size: 28, t: fixedT ?? 0)).interpolation(.none)
            bubble(a.announcement, size: 11, night: night)
        }
        .frame(maxWidth: 230, alignment: .leading)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        Button { model.dismissAward() } label: {
            Text(L.t("Thanks, magpie", "고마워, 까치야", "ありがとう、カササギ", "谢谢你，喜鹊"))
                .font(.caption.weight(.bold)).foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(TitleCard.gold))
        }
        .buttonStyle(.plain)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private func bubble(_ text: String, size: CGFloat, night: Bool) -> some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundColor(night ? .white : Color(red: 0.16, green: 0.13, blue: 0.11))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(night ? 0.14 : 0.82)))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sceneImage(_ s: Snapshot, t: Double) -> some View {
        Image(nsImage: Yugong.scene(info(s, t: t), t: t, size: Self.sceneSize))
            .interpolation(.none)
            .frame(width: Self.sceneSize.width, height: Self.sceneSize.height)
    }

    private var mountainRow: some View {
        let m = model.mountain, left = model.mountainLeft
        let carried = model.demoMountainLeft.map { (1 - $0) * m.size } ?? m.tokens
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.t("\(m.name): \(Int(((1 - left) * 100).rounded()))% carried away",
                         "\(m.name) \(Int(((1 - left) * 100).rounded()))% 옮김",
                         "\(m.name) \(Int(((1 - left) * 100).rounded()))% 運んだ",
                         "\(m.name) 已搬走 \(Int(((1 - left) * 100).rounded()))%"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(L.t("\(Fmt.tokens(Int(carried))) tokens so far",
                         "지금까지 \(Fmt.tokens(Int(carried))) 토큰",
                         "これまで \(Fmt.tokens(Int(carried))) トークン",
                         "累计 \(Fmt.tokens(Int(carried))) token"))
                    .font(.caption).foregroundColor(.secondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(Color(red: 0.75, green: 0.28, blue: 0.23)).frame(width: max(4, g.size.width * CGFloat(1 - left)))
                }
            }
            .frame(height: 6)
        }
    }

    private var cutsceneLine: String {
        L.t("Heaven was moved, and sent Kua'e's two sons to carry the mountain away!",
            "하늘이 감동해 과아씨의 두 아들을 보내 산을 업어 가게 했어요!",
            "天が心を打たれ、夸娥氏の二人の息子に山を背負って運ばせました！",
            "天帝被感动，派夸娥氏的两个儿子把山背走了！")
    }

    private var finaleLine: String {
        L.t("Kua'e's two sons carry the mountains away: one to the east, one to the south. The road is open!",
            "과아씨의 두 아들이 산 하나는 동쪽, 하나는 남쪽으로 옮겨요. 이제 길이 막힘없이 뚫렸어요!",
            "夸娥氏の二人の息子が、山を一つは東へ、一つは南へ運びます。道がまっすぐ開けました！",
            "夸娥氏的两个儿子把一座山背到东边，一座背到南边。从此道路畅通！")
    }

    private func stateTitle(_ st: PetState) -> String {
        if !model.snap.known { return L.t("Grandpa doesn't know your limits", "할아버지도 한도를 몰라요", "おじいさんにもリミットがわかりません", "爷爷也不知道你的额度") }
        switch st {
        case .lively:    return L.t("Grandpa is digging happily", "할아버지 신나게 파는 중", "おじいさん、楽しく掘っています", "爷爷正开心地挖着")
        case .steady:    return L.t("Steady digging", "꾸준히 파는 중", "こつこつ掘っています", "稳稳地挖着")
        case .straining: return model.snap.daily != nil ? L.t("Ahead of today's share: take it slow",
                                                              "오늘 몫 넘음 · 천천히",
                                                              "今日の取り分超え・ゆっくりと",
                                                              "超过今日份额 · 慢慢来")
                                                        : L.t("Grandpa is straining", "할아버지 힘에 부쳐요", "おじいさん、息が上がっています", "爷爷有点吃力")
        case .resting:
            guard let w = model.snap.wakeAt else { return L.t("Carrier full: resting", "지게 가득 · 쉬는 중", "背負子いっぱい・休憩中", "背架满了 · 休息中") }
            let u = Fmt.until(w, now: clockNow)
            return L.t("Resting · back \(u)", "쉬는 중 · \(u) 다시 퍼요", "休憩中・\(u)に再開", "休息中 · \(u)接着挖")
        case .morning:   return L.t("Morning! Fresh carrier", "아침이에요 · 지게 비움", "朝です・背負子は空っぽ", "早上好 · 背架清空了")
        }
    }

    private func speech(_ s: Snapshot) -> String {
        if !s.known { return L.t("Don't know how full the carrier is.", "지게가 얼마나 찼는지 모르겠구먼.", "背負子がどれだけ詰まっとるか、わからんのう。", "背架装了多少，我也不知道哇。") }
        switch s.state {
        case .lively:
            return model.night ? L.t("Yawn… still digging this late?", "하암… 밤이 깊었구먼", "ふわぁ…夜も更けたのう", "哈欠…夜深了哟")
                               : L.t("One shovel, one shovel less mountain!",
                                     "한 삽이면 한 삽만큼 줄지, 허허!",
                                     "ひとすくい掘れば、ひとすくい分減るんじゃ、ほっほっ！",
                                     "挖一锹，山就少一锹，呵呵！")
        case .steady:    return L.t("Steady now, steady.", "쉬엄쉬엄, 꾸준히 가세.", "ぼちぼち、こつこつじゃ。", "慢慢来，稳稳地挖。")
        case .straining:
            return s.daily != nil ? L.t("Past today's share. Easy, the week is long.",
                                        "오늘 몫은 넘었구먼. 천천히 하세, 한 주는 길어",
                                        "今日の分は超えたのう。ゆっくりやろう、一週間は長いぞ",
                                        "今天的份额超了。慢点儿，一周还长着呢")
                                  : L.t("Oof, my back… slow down a bit?", "어이구 허리야… 좀 천천히 퍼세", "あいたた、腰が…ちと、ゆっくり掘らんか", "哎哟我的腰…挖慢一点吧")
        case .resting:
            let w = s.wakeAt.map { Fmt.clock($0, now: clockNow) } ?? "?"
            return L.t("Carrier's full.\nBack to digging at \(w)",
                       "지게가 꽉 찼구먼.\n\(w)에 다시 퍼요",
                       "背負子がいっぱいじゃ。\n\(w)にまた掘るぞ",
                       "背架装满啦。\n\(w) 再接着挖")
        case .morning:   return L.t("Morning! Shovel's waiting.", "에헴, 아침이구먼! 다시 퍼 볼까", "おほん、朝じゃ！また掘るとするか", "咳咳，天亮啦！接着挖吧")
        }
    }

    /// `pace`: a pace guide, not a limit, so 100% and over is not drawn as "full, resting".
    @ViewBuilder private func meterRow(_ label: String, _ m: Meter?, pace: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                if let m {
                    Text(pace ? "\(Int(m.pct.rounded()))%" : Fmt.pct(m.pct)).font(.subheadline.monospacedDigit().weight(.semibold))
                } else {
                    Text(L.t("don't know", "모름", "わからない", "不知道")).font(.caption).foregroundColor(.secondary)
                }
            }
            GeometryReader { g in
                let p = min(1, max(0, (m?.pct ?? 0) / 100))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(barColor(pace ? min(m?.pct ?? 0, 99) : m?.pct ?? 0)).frame(width: max(p > 0 ? 8 : 0, g.size.width * p))
                }
            }
            .frame(height: 8)
            Text(resetText(m)).font(.caption).foregroundColor(.secondary)
        }
    }

    private func barColor(_ p: Double) -> Color {
        p >= 100 ? Color(red: 0.42, green: 0.45, blue: 0.85) : p >= 80 ? Color(red: 0.96, green: 0.45, blue: 0.35) : Color(red: 0.30, green: 0.72, blue: 0.52)
    }

    /// " (resets Mon 04:00)", or nothing while the weekly reset time is unknown.
    private func weeklyReset(_ s: Snapshot) -> String {
        guard let r = s.week?.resetsAt else { return "" }
        return L.t(" (resets \(Fmt.clock(r, now: clockNow)))",
                   "(\(Fmt.clock(r, now: clockNow)) 리셋)",
                   "（\(Fmt.clock(r, now: clockNow))にリセット）",
                   "（\(Fmt.clock(r, now: clockNow)) 重置）")
    }

    private func resetText(_ m: Meter?) -> String {
        guard let m else { return " " }
        guard let r = m.resetsAt else { return L.t("fresh window — starts with your next message",
                                                   "새 구간 — 다음 메시지부터 시작",
                                                   "新しい区間 — 次のメッセージから開始",
                                                   "新的时段 — 从下一条消息开始") }
        return L.t("resets \(Fmt.clock(r, now: clockNow)) (\(Fmt.until(r, now: clockNow)))",
                   "\(Fmt.clock(r, now: clockNow)) 리셋 (\(Fmt.until(r, now: clockNow)))",
                   "\(Fmt.clock(r, now: clockNow))にリセット（\(Fmt.until(r, now: clockNow))）",
                   "\(Fmt.clock(r, now: clockNow)) 重置（\(Fmt.until(r, now: clockNow))）")
    }

    /// The windows a reading has: 5-hour, weekly, and a billed API's month.
    @ViewBuilder private func windowRows(_ r: Reading) -> some View {
        if r.five == nil && r.week == nil && r.month == nil { meterRow(L.t("Limit", "한도", "リミット", "额度"), nil) }
        if let f = r.five { meterRow(L.t("5-hour", "5시간", "5時間", "5 小时"), f) }
        if let w = r.week { meterRow(L.t("Weekly", "주간", "週間", "每周"), w) }
        if let m = r.month { meterRow(L.t("This month's budget", "이번 달 예산", "今月の予算", "本月预算"), m) }
    }

    @ViewBuilder private func note(_ text: String) -> some View {
        if !text.isEmpty { Text(text).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true) }
    }

    /// Where an AI's numbers come from, or why there are none. `at` = when the numbers were reported.
    private func source(_ p: Provider, _ at: Date?) -> String {
        let when = at.map { Fmt.clock($0, now: clockNow) + " · " + Fmt.ago($0, now: clockNow) } ?? ""
        let budget = model.budgets.state[p]
        switch p {
        case .claude:
            return at != nil ? L.t("Limits from Claude Code's status line, as of \(when) (they can only have grown since).",
                                   "Claude Code 상태줄의 공식 한도 · \(when) 기준 (그 뒤로는 늘었을 수만 있어요)",
                                   "Claude Code のステータスラインの公式リミット・\(when)時点（その後は増えたかもしれません）",
                                   "来自 Claude Code 状态栏的官方额度，截至 \(when)（之后只可能增加）。")
                             : L.t("No limits from Claude Code yet. Connect its status line (Settings › How it works); until then he says he doesn't know.",
                                   "아직 Claude Code 한도 정보가 없어요. 상태줄을 연결하면 보여요(설정 › 사용법과 Claude Code 연결). 그 전에는 모른다고 말해요.",
                                   "Claude Code のリミットはまだありません。ステータスラインを接続すると表示されます（設定 › 使い方）。それまでは「わからない」と言います。",
                                   "还没有来自 Claude Code 的额度。连接它的状态栏后就会显示（设置 › 使用说明）；在那之前他会说不知道。")
        case .codex:
            return at != nil ? L.t("From Codex CLI logs, as of \(when).",
                                   "Codex CLI 기록 · \(when) 기준",
                                   "Codex CLI のログ・\(when)時点",
                                   "来自 Codex CLI 日志，截至 \(when)。")
                             : L.t("No Codex CLI logs with limits on this Mac yet.",
                                   "이 Mac에 한도가 적힌 Codex CLI 기록이 아직 없어요.",
                                   "この Mac にはリミットが書かれた Codex CLI のログがまだありません。",
                                   "这台 Mac 上还没有带额度的 Codex CLI 日志。")
        case .gemini:
            return L.t("Gemini CLI keeps no limits on this Mac, so he can't say how full it is. Its tokens still move the mountain.",
                       "Gemini CLI는 이 Mac에 한도를 남기지 않아서 얼마나 찼는지 몰라요. 토큰은 산 옮기기에 들어가요.",
                       "Gemini CLI はこの Mac にリミットを残さないので、どれだけ詰まったかはわかりません。トークンは山を移すのに数えます。",
                       "Gemini CLI 不在这台 Mac 上记录额度，所以不知道用了多少。它的 token 仍会用来搬山。")
        case .openai:
            if let pr = budget?.problem { return "OpenAI: \(pr.text)" }
            if let sp = budget?.spent {
                return model.openAIBudget > 0
                    ? L.t(String(format: "OpenAI costs this month: $%.2f of a $%.0f budget, as of %@.", sp, model.openAIBudget, when),
                          String(format: "OpenAI 이번 달 비용: $%.2f / 예산 $%.0f · %@ 기준", sp, model.openAIBudget, when),
                          String(format: "OpenAI の今月の費用：$%.2f / 予算 $%.0f・%@時点", sp, model.openAIBudget, when),
                          String(format: "OpenAI 本月费用：$%.2f / 预算 $%.0f，截至 %@。", sp, model.openAIBudget, when))
                    : L.t(String(format: "OpenAI costs this month: $%.2f. Set a monthly budget (Settings › Family) to fill the meter.", sp),
                          String(format: "OpenAI 이번 달 비용: $%.2f. 설정 › 식구에서 월 예산을 넣으면 미터가 차요.", sp),
                          String(format: "OpenAI の今月の費用：$%.2f。設定 › 家族で月の予算を入れるとメーターが満ちます。", sp),
                          String(format: "OpenAI 本月费用：$%.2f。在 设置 › 家人 中设定月度预算后，额度表就会显示。", sp))
            }
            return L.t("Add an OpenAI Admin key and a monthly budget (Settings › Family).",
                       "설정 › 식구에서 OpenAI 관리자(Admin) 키와 월 예산을 넣어 주세요.",
                       "設定 › 家族で OpenAI の管理者（Admin）キーと月の予算を入れてください。",
                       "请在 设置 › 家人 中填写 OpenAI 管理员（Admin）密钥和月度预算。")
        case .deepseek:
            if let pr = budget?.problem { return "DeepSeek: \(pr.text)" }
            if let b = budget?.balance {
                return L.t("DeepSeek reports only the balance (\(b)), not what was spent, so he can't say how full it is.",
                           "DeepSeek은 잔액(\(b))만 알려 주고 쓴 돈은 알려 주지 않아서 얼마나 찼는지 몰라요.",
                           "DeepSeek は残高（\(b)）だけを伝え、使った金額は教えてくれないので、どれだけ詰まったかはわかりません。",
                           "DeepSeek 只报告余额（\(b)），不报告花了多少，所以不知道用了多少。")
            }
            return L.t("DeepSeek reports only a balance, never the spend. Add a key to see the balance (Settings › Family).",
                       "DeepSeek은 쓴 돈 없이 잔액만 알려 줘요. 설정 › 식구에서 키를 넣으면 잔액이 보여요.",
                       "DeepSeek は使った金額ではなく残高だけを伝えます。設定 › 家族でキーを入れると残高が見えます。",
                       "DeepSeek 只报告余额，从不报告花费。在 设置 › 家人 中添加密钥即可查看余额。")
        }
    }

    @State private var keyDraft: [Provider: String] = [:]

    /// Settings › Family: who watches which AI, the OpenAI budget, API keys (kept in the Keychain).
    @ViewBuilder private var familySettings: some View {
        Text(L.t("Family: who watches which AI",
                 "식구: 누가 어떤 AI를 맡나",
                 "家族：だれがどの AI を受け持つか",
                 "家人：谁看管哪个 AI")).font(.caption.weight(.bold)).foregroundColor(.secondary)
        ForEach(Role.allCases) { role in
            Picker(role.name, selection: Binding(get: { model.family.roles[role] }, set: { model.family = model.family.assigning($0, to: role) })) {
                if role != .grandpa { Text(L.t("Nobody", "없음", "だれもいない", "无人")).tag(Provider?.none) }
                ForEach(Provider.allCases) { p in Text(p.name).tag(Optional(p)) }
            }
        }
        if model.family.roles.values.contains(.openai) {
            HStack {
                Text(L.t("OpenAI monthly budget (USD)", "OpenAI 월 예산 (USD)", "OpenAI 月の予算（USD）", "OpenAI 月度预算（美元）"))
                TextField("", value: $model.openAIBudget, format: .number).frame(width: 80)
            }
        }
        ForEach(Provider.allCases.filter { $0.billed && model.family.roles.values.contains($0) }) { p in
            HStack {
                SecureField(p == .openai ? L.t("OpenAI Admin key", "OpenAI 관리자 키", "OpenAI 管理者キー", "OpenAI 管理员密钥")
                                         : L.t("DeepSeek API key", "DeepSeek API 키", "DeepSeek API キー", "DeepSeek API 密钥"),
                            text: Binding(get: { keyDraft[p] ?? "" }, set: { keyDraft[p] = $0 }))
                Button(L.t("Save", "저장", "保存", "保存")) { model.setKey(keyDraft[p], for: p); keyDraft[p] = nil }
                    .disabled((keyDraft[p] ?? "").isEmpty)
                if Keychain.key(p) != nil { Button(L.t("Remove", "지우기", "削除", "删除")) { model.setKey(nil, for: p) } }
            }
        }
    }
}
