import SwiftUI
import TokenPetAssets

enum L {
    static var korean = resolve(Prefs.store.string(forKey: "language") ?? "auto")
    /// The language setting ("auto", "ko", "en") -> Korean or not.
    static func resolve(_ pref: String, system: [String] = Locale.preferredLanguages) -> Bool {
        pref == "auto" ? (system.first ?? "en").hasPrefix("ko") : pref == "ko"
    }
    static func t(_ en: String, _ ko: String) -> String { korean ? ko : en }
}

enum Fmt {
    static func clock(_ d: Date, now: Date = Date(), tz: TimeZone = .current, korean: Bool = L.korean) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let f = DateFormatter()
        f.locale = Locale(identifier: korean ? "ko_KR" : "en_US"); f.timeZone = tz
        f.dateFormat = cal.isDate(d, inSameDayAs: now) ? "HH:mm" : (korean ? "E HH:mm" : "EEE HH:mm")
        return f.string(from: d)
    }
    static func until(_ d: Date, now: Date = Date()) -> String {
        let m = max(0, Int(d.timeIntervalSince(now) / 60))
        if m >= 24 * 60 { return L.t("in \(m / 1440)d \((m % 1440) / 60)h", "\(m / 1440)일 \((m % 1440) / 60)시간 뒤") }
        if m >= 60 { return L.t("in \(m / 60)h \(m % 60)m", "\(m / 60)시간 \(m % 60)분 뒤") }
        return L.t("in \(m)m", "\(m)분 뒤")
    }
    /// Compact time left for the menu bar: "5d 2h", "3h 12m", "12m".
    static func left(_ d: Date, now: Date = Date()) -> String {
        let m = max(0, Int(d.timeIntervalSince(now) / 60))
        if m >= 24 * 60 { return "\(m / 1440)d \((m % 1440) / 60)h" }
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return "\(m)m"
    }
    static func tokens(_ n: Int) -> String {
        if L.korean {
            if n >= 100_000_000 { return String(format: "%.1f억", Double(n) / 1e8) }
            if n >= 10_000 { return "\(n / 10_000)만" }
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

    static let sceneSize = CGSize(width: 292, height: 176)
    @State var showSettings = args.contains("--settings")   // demo: open with settings shown

    var body: some View {
        let s = model.snap
        VStack(alignment: .leading, spacing: 10) {
            scene(s)
            HStack(alignment: .firstTextBaseline) {
                Text(model.cutsceneDue ? L.t("The mountain is moving!", "산이 옮겨져요!") : stateTitle(s.state))
                    .font(.system(.headline, design: .rounded))
                Spacer()
                if let d = BarText.detail(s, now: clockNow) {
                    Text(d).font(.subheadline.monospacedDigit().weight(.semibold)).foregroundColor(.secondary)
                }
            }
            mountainRow
            Text(L.t("Claude · Grandpa's carrier", "Claude · 할아버지 지게")).font(.caption.weight(.bold)).foregroundColor(.secondary)
            if let d = s.daily {
                // no 5-hour window on this account: the weekly limit is the carrier, today's share only sets the pace
                meterRow(L.t("Weekly (the carrier)", "주간 (지게)"), s.week)
                meterRow(L.t("Today's share: pace (1/7 of the week)", "오늘 몫: 속도 (주간의 1/7)"), Meter(pct: d.fill * 100, resetsAt: d.dayEnd), pace: true)
                Text(L.t("No 5-hour limit on this account, only weekly. Grandpa naps only when the weekly limit runs out\(weeklyReset(s)); going past today's share just makes him sweat.",
                         "이 계정은 5시간 한도 없이 주간 한도만 있어요. 할아버지는 주간 한도를 다 쓸 때만 쉬어요\(weeklyReset(s)). 오늘 몫을 넘으면 땀만 흘려요."))
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                meterRow(L.t("5-hour", "5시간"), s.five)
                meterRow(L.t("Weekly", "주간"), s.week)
            }
            if let p = s.projected, s.known, s.state != .resting, s.daily == nil {
                Text(L.t("At this pace: about \(Int(p.rounded()))% by the reset", "이 속도면 리셋 때 약 \(Int(p.rounded()))%"))
                    .font(.caption).foregroundColor(p >= 100 ? Color(red: 0.8, green: 0.3, blue: 0.2) : .secondary)
            }
            sourceNote(s)
            if !s.demo {
                Text(L.t("Shovel speed: \(Int(model.pace.smoothed.rounded())) output tokens/min (last 3 min, this Mac)",
                         "삽질 속도: 분당 출력 토큰 \(Int(model.pace.smoothed.rounded())) (최근 3분, 이 Mac)"))
                    .font(.caption).foregroundColor(.secondary)
            }
            if let c = s.codex, model.showCodex {
                Divider()
                HStack {
                    Text(L.t("Codex · grandson's basket", "Codex · 손주 바구니")).font(.caption.weight(.bold)).foregroundColor(.secondary)
                    Spacer()
                    Text(L.t("from Codex CLI logs · \(Fmt.clock(c.at, now: clockNow))", "Codex CLI 기록 · \(Fmt.clock(c.at, now: clockNow))"))
                        .font(.caption2).foregroundColor(.secondary)
                }
                if let f = c.five { meterRow(L.t("5-hour", "5시간"), f) }
                if let w = c.week { meterRow(L.t("Weekly", "주간"), w) }
            }
            Button { model.hideFromCapture.toggle() } label: {
                HStack(spacing: 6) {
                    let hidden = model.hideFromCapture && !model.captureAllowedForDemo
                    Image(systemName: hidden ? "eye.slash.fill" : "eye")
                    Text(model.captureAllowedForDemo ? L.t("Capture allowed for this demo recording", "데모 녹화를 위해 잠시 캡처 허용")
                         : hidden ? L.t("Hidden from screen sharing", "화면 공유·녹화에서 숨김")
                                  : L.t("Visible in screen sharing", "화면 공유·녹화에 보임"))
                }
                .font(.caption)
            }
            .buttonStyle(.plain).foregroundColor(.secondary)
            if showSettings { settings }
            HStack {
                Button { showSettings.toggle() } label: { Image(systemName: showSettings ? "gearshape.fill" : "gearshape") }
                    .buttonStyle(.plain).foregroundColor(.secondary).help(L.t("Settings", "설정"))
                if model.demo != nil || model.demoCycle || model.demoCutscene {
                    Text(L.t("Demo data", "데모 데이터")).font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                }
                Spacer()
                Button(L.t("Refresh", "새로고침")) { model.refresh() }.disabled(model.scanning)
                Button(L.t("Quit", "종료")) { NSApp.terminate(nil) }
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
            Text(L.t("Settings", "설정")).font(.caption.weight(.bold)).foregroundColor(.secondary)
            Picker(L.t("Language", "언어"), selection: $model.language) {
                Text(L.t("System", "시스템")).tag("auto")
                Text("한국어").tag("ko")
                Text("English").tag("en")
            }
            Toggle(L.t("Grandpa in the menu bar", "메뉴바에 할아버지"), isOn: $model.barGrandpa)
            Picker(L.t("Menu bar number", "메뉴바 숫자"), selection: $model.barText) {
                Text(L.t("Percent used (24%)", "사용한 % (24%)")).tag(BarText.percent)
                Text(L.t("Time to reset (3h 12m)", "리셋까지 (3h 12m)")).tag(BarText.timeLeft)
                Text(L.t("Reset time (Mon 04:00)", "리셋 시각 (월 04:00)")).tag(BarText.resetClock)
                Text(L.t("None", "없음")).tag(BarText.none)
            }
            Picker(L.t("Mini window", "작은 창"), selection: $model.miniMode) {
                Text(L.t("When the menu bar is full", "메뉴바가 꽉 찼을 때")).tag(MiniMode.auto)
                Text(L.t("Always", "항상")).tag(MiniMode.always)
                Text(L.t("Never", "끔")).tag(MiniMode.off)
            }
            Toggle(L.t("Show the grandson (Codex)", "손주(Codex) 보이기"), isOn: $model.showCodex)
            let login = model.launchAtLogin
            Toggle(L.t("Open at login", "로그인할 때 열기"), isOn: Binding(get: { login == .enabled || login == .requiresApproval },
                                                                       set: { model.setLaunchAtLogin($0) }))
                .disabled(!model.canLaunchAtLogin)
                .help(model.canLaunchAtLogin ? "" : L.t("Only in the app bundle (scripts/bundle.sh)", "앱 번들에서만 (scripts/bundle.sh)"))
            if login == .requiresApproval {
                Text(L.t("Allow it in System Settings › General › Login Items.", "시스템 설정 › 일반 › 로그인 항목에서 허용해 주세요."))
                    .font(.caption).foregroundColor(.secondary)
            }
            Button(L.t("How it works and Claude Code setup…", "사용법과 Claude Code 연결…")) { model.openGuide?() }
                .buttonStyle(.link)
        }
        .font(.callout)
    }

    private func info(_ s: Snapshot, t: Double) -> SceneInfo {
        var i = SceneInfo(state: s.state, carrier: s.carrier, mountainLeft: model.mountainLeft, grandson: model.showCodex ? s.codexFill : nil,
                          night: s.state == .resting || model.night,
                          cutscene: model.cutsceneDue ? (cutsceneT ?? model.cutsceneStart.map { min(1, Date().timeIntervalSince($0) / 4.5) }
                                                         ?? (t / 7).truncatingRemainder(dividingBy: 1)) : nil)
        i.tempo = model.tempo
        return i
    }

    @ViewBuilder private func scene(_ s: Snapshot) -> some View {
        let night = !model.cutsceneDue && (s.state == .resting || model.night)   // the cutscene sky is always golden
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
            Text(model.cutsceneDue ? cutsceneLine : speech(s))
                .font(.system(size: model.cutsceneDue ? 12 : 13, weight: .semibold, design: .rounded))
                .foregroundColor(night ? .white : Color(red: 0.16, green: 0.13, blue: 0.11))
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(night ? 0.14 : 0.82)))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: model.cutsceneDue ? 250 : 150, alignment: .trailing)   // the cutscene line stays above his head
                .padding(10)
            if model.cutsceneDue {
                Button { model.finishCutscene() } label: {
                    Text(L.t("On to the next mountain", "다음 산으로"))
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
                Text(L.t("\(m.name): \(Int(((1 - left) * 100).rounded()))% carried away", "\(m.name) \(Int(((1 - left) * 100).rounded()))% 옮김"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(L.t("\(Fmt.tokens(Int(carried))) tokens so far", "지금까지 \(Fmt.tokens(Int(carried))) 토큰"))
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
        L.t("Heaven was moved by his stubbornness, and had the mountain carried away!",
            "하늘이 할아버지의 끈기에 감동해 산을 옮겨 주었어요!")
    }

    private func stateTitle(_ st: PetState) -> String {
        if !model.snap.known { return L.t("Grandpa doesn't know your limits", "할아버지도 한도를 몰라요") }
        switch st {
        case .lively:    return L.t("Grandpa is digging happily", "할아버지 신나게 파는 중")
        case .steady:    return L.t("Steady digging", "꾸준히 파는 중")
        case .straining: return model.snap.daily != nil ? L.t("Ahead of today's share: take it slow", "오늘 몫 넘음 · 천천히")
                                                        : L.t("Grandpa is straining", "할아버지 힘에 부쳐요")
        case .resting:   return L.t("Carrier full: resting", "지게 가득 · 쉬는 중")
        case .morning:   return L.t("Morning! Fresh carrier", "아침이에요 · 지게 비움")
        }
    }

    private func speech(_ s: Snapshot) -> String {
        if !s.known { return L.t("Don't know how full the carrier is.", "지게가 얼마나 찼는지 모르겠구먼.") }
        switch s.state {
        case .lively:
            return model.night ? L.t("Yawn… still digging this late?", "하암… 밤이 깊었구먼")
                               : L.t("One shovel, one shovel less mountain!", "한 삽이면 한 삽만큼 줄지, 허허!")
        case .steady:    return L.t("Steady now, steady.", "쉬엄쉬엄, 꾸준히 가세.")
        case .straining:
            return s.daily != nil ? L.t("Past today's share. Easy, the week is long.", "오늘 몫은 넘었구먼. 천천히 하세, 한 주는 길어")
                                  : L.t("Oof, my back… slow down a bit?", "어이구 허리야… 좀 천천히 퍼세")
        case .resting:
            let w = s.wakeAt.map { Fmt.clock($0, now: clockNow) } ?? "?"
            return L.t("Carrier's full.\nBack to digging at \(w)", "지게가 꽉 찼구먼.\n\(w)에 다시 퍼요")
        case .morning:   return L.t("Morning! Shovel's waiting.", "에헴, 아침이구먼! 다시 퍼 볼까")
        }
    }

    /// `pace`: a pace guide, not a limit, so 100% and over is not drawn as "full, resting".
    @ViewBuilder private func meterRow(_ label: String, _ m: Meter?, pace: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                if let m {
                    Text("\(Int(m.pct.rounded()))%").font(.subheadline.monospacedDigit().weight(.semibold))
                } else {
                    Text(L.t("don't know", "모름")).font(.caption).foregroundColor(.secondary)
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
        return L.t(" (resets \(Fmt.clock(r, now: clockNow)))", "(\(Fmt.clock(r, now: clockNow)) 리셋)")
    }

    private func resetText(_ m: Meter?) -> String {
        guard let m else { return " " }
        guard let r = m.resetsAt else { return L.t("fresh window — starts with your next message", "새 구간 — 다음 메시지부터 시작") }
        return L.t("resets \(Fmt.clock(r, now: clockNow)) (\(Fmt.until(r, now: clockNow)))", "\(Fmt.clock(r, now: clockNow)) 리셋 (\(Fmt.until(r, now: clockNow)))")
    }

    private func sourceNote(_ s: Snapshot) -> some View {
        let text: String
        if s.demo { text = L.t("Simulated state for preview.", "미리보기용 가상 상태입니다.") }
        else if let cap = s.captured {
            text = L.t("Limits from Claude Code's status line, as of \(Fmt.clock(cap, now: clockNow)) (they can only have grown since).",
                       "Claude Code 상태줄의 공식 한도 · \(Fmt.clock(cap, now: clockNow)) 기준 (그 뒤로는 늘었을 수만 있어요)")
        } else {
            text = L.t("No limits from Claude Code yet. Connect its status line (Settings › How it works); until then Grandpa says he doesn't know.",
                       "아직 Claude Code 한도 정보가 없어요. 상태줄을 연결하면 보여요(설정 › 사용법과 Claude Code 연결). 그 전에는 모른다고 말해요.")
        }
        return Text(text).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
