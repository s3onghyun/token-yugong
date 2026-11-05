import Foundation
import ServiceManagement
import TokenPetAssets

/// One settings domain however the app is started (`swift run` or the .app bundle), so the
/// mountain and the settings carry over. `defaults delete TokenPet` clears everything.
/// TOKENPET_PREFS names another domain (tests and demo recordings, so they leave yours alone).
enum Prefs {
    static let domain = ProcessInfo.processInfo.environment["TOKENPET_PREFS"] ?? "TokenPet"
    static let store = UserDefaults(suiteName: domain) ?? .standard
}

/// What the app read from the bridge and made of it, one line per new reading, for telling later which
/// account it showed and why. Hashed account ids, reset times and percentages only; on this Mac, in
/// ~/Library/Application Support/<settings domain>/, at most two files of 512 KB (a few days).
enum ReadingLog {
    static let limit = 512 * 1024
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Prefs.domain).appendingPathComponent("claude-readings.log")
    }

    static func append(_ line: String, to url: URL = url) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > limit {
            let old = url.appendingPathExtension("1")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// `5h=14%@11:40 week=33%@11-04 22:00` (local time; `-` = no window, `@?` = reset not known).
    static func describe(_ r: Reading?) -> String {
        func m(_ x: Meter?, _ f: String) -> String {
            guard let x else { return "-" }
            return "\(Int(x.pct.rounded()))%@" + (x.resetsAt.map { stamp($0, f) } ?? "?")
        }
        guard let r else { return "none" }
        return "5h=\(m(r.five, "HH:mm")) week=\(m(r.week, "MM-dd HH:mm"))"
    }

    static func line(read r: Reading, decision: String, shown: Reading?, accounts a: Accounts) -> String {
        "\(stamp(Date(), "yyyy-MM-dd'T'HH:mm:ssZ")) captured=\(stamp(r.at, "HH:mm:ss")) account=\(r.account ?? "-") "
            + "\(describe(r)) -> \(decision) current=\(a.letter.map { "\($0):\(a.id ?? "")" } ?? "unnamed") shown: \(describe(shown))"
    }

    private static func stamp(_ d: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = format
        return f.string(from: d)
    }
}

// MARK: - Codex CLI (local session logs; no network, no credentials)

/// Codex writes `rate_limits` into ~/.codex/sessions/**/rollout-*.jsonl on every `token_count`
/// event, with the response's token usage. Reads the newest 5 recent files, only when they change.
final class CodexReader {
    let root: URL
    private(set) var reading: Reading?
    private(set) var events: [LogScanner.Event] = []   // for the shovel speed and the mountain
    private var seenFiles: [String] = []

    init(root: URL) { self.root = root }

    func scan(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-8 * 86400)
        var files: [(URL, Date)] = []
        if let it = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            for case let u as URL in it where u.pathExtension == "jsonl" {
                if let m = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, m >= cutoff { files.append((u, m)) }
            }
        }
        let newest = files.sorted { $0.1 > $1.1 }.prefix(5)
        let key = newest.map { "\($0.0.path)@\($0.1.timeIntervalSince1970)" }
        guard key != seenFiles else { return }
        seenFiles = key
        var reading: Reading?, events: [LogScanner.Event] = []
        for (u, _) in newest {
            guard let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.contains("\"token_count\"") {
                let data = Data(line.utf8)
                if let r = Limits.codex(data), r.at > (reading?.at ?? .distantPast) { reading = r }
                if let e = Self.output(data) { events.append(e) }
            }
        }
        self.reading = reading
        self.events = events.filter { $0.time > cutoff }.sorted { $0.time < $1.time }
    }

    /// One response's tokens: input without the cached part (as Claude counts) plus output.
    static func output(_ line: Data) -> LogScanner.Event? {
        guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let p = o["payload"] as? [String: Any], let info = p["info"] as? [String: Any],
              let last = info["last_token_usage"] as? [String: Any], let n = last["output_tokens"] as? Int,
              let t = (o["timestamp"] as? String).flatMap(Limits.iso.date(from:)) else { return nil }
        let input = max(0, (last["input_tokens"] as? Int ?? 0) - (last["cached_input_tokens"] as? Int ?? 0))
        return LogScanner.Event(time: t, tokens: input + n, output: n)
    }
}

// MARK: - The mountain: cumulative tokens, kept on this Mac

/// Every token Grandpa has shovelled since the app first ran, persisted in UserDefaults.
/// A mountain is `size` tokens; when it is all carried away the milestone cutscene is due and
/// the next mountain appears (Taihang first, then Wangwu, as in the tale).
struct MountainLedger {
    static let defaultSize: Double = 1_000_000_000
    var tokens: Double
    var through: Date?          // newest log event already counted
    var index: Int              // 0 = Taihang, 1 = Wangwu, then "another mountain"
    var cutscenePending: Bool
    let size: Double
    var store: UserDefaults = Prefs.store

    static func load(_ d: UserDefaults = Prefs.store) -> MountainLedger {
        MountainLedger(tokens: d.double(forKey: "mountain.tokens"),
                       through: (d.object(forKey: "mountain.through") as? Double).map(Date.init(timeIntervalSince1970:)),
                       index: d.integer(forKey: "mountain.index"),
                       cutscenePending: d.bool(forKey: "mountain.cutscene"),
                       size: (d.object(forKey: "mountain.size") as? Double) ?? defaultSize, store: d)
    }

    func save() {
        let d = store
        d.set(tokens, forKey: "mountain.tokens")
        d.set(through?.timeIntervalSince1970, forKey: "mountain.through")
        d.set(index, forKey: "mountain.index")
        d.set(cutscenePending, forKey: "mountain.cutscene")
    }

    /// Adds log events newer than the last counted one. The first run counts the week already in the logs.
    mutating func absorb(_ events: [LogScanner.Event]) {
        let fresh = events.filter { through == nil || $0.time > through! }
        guard let last = fresh.last else { return }
        tokens += Double(fresh.reduce(0) { $0 + $1.tokens })
        through = last.time
        if tokens >= size && !cutscenePending { cutscenePending = true }   // hook: the heavenly emperor is moved
        save()
    }

    /// After the cutscene: the mountain is gone, the next one starts.
    mutating func nextMountain() {
        cutscenePending = false
        tokens = max(0, tokens - size)
        index += 1
        save()
    }

    var left: Double { max(0, 1 - tokens / size) }
    /// Every token carried, all mountains together (the titles ladder).
    var lifetime: Double { Double(index) * size + tokens }
    var name: String {
        switch index {
        case 0: return L.t("Mount Taihang", "태행산", "太行山", "太行山")
        case 1: return L.t("Mount Wangwu", "왕옥산", "王屋山", "王屋山")
        default: return L.t("Mountain #\(index + 1)", "\(index + 1)번째 산", "\(index + 1)番目の山", "第 \(index + 1) 座山")
        }
    }
}

/// Which Claude account is current and its numbers, saved so a restart still ignores the old account's
/// sessions. Only reset times, percentages and the bridge's hashed account ids: no name, no raw id.
extension Accounts {
    static func load(_ d: UserDefaults = Prefs.store) -> Accounts {
        d.data(forKey: "claude.account").flatMap { try? JSONDecoder().decode(Accounts.self, from: $0) } ?? Accounts()
    }

    func save(_ d: UserDefaults = Prefs.store) { d.set(try? JSONEncoder().encode(self), forKey: "claude.account") }
}

// MARK: - Model

final class UsageModel: ObservableObject {
    @Published private(set) var snap = Snapshot()
    @Published private(set) var pace = Pace()
    @Published private(set) var scanning = false
    @Published private(set) var mountain = MountainLedger.load()
    @Published private(set) var titles = TitleBook.load()
    /// Newly earned titles and achievements, oldest first: the popover celebrates the first one.
    @Published private(set) var awards: [Award] = []
    /// Set by the app: a notification per award.
    var onAward: ((Award) -> Void)?
    /// Set by the app: Grandpa's limit was just used up (true) or has reset (false).
    var onLimit: ((Snapshot) -> Void)?
    /// Demo override for every token carried (`--lifetime <tokens>`).
    var demoLifetime: Double?
    var lifetime: Double { demoLifetime ?? mountain.lifetime }
    /// Demo override for the mountain (fraction left) and the cutscene.
    var demoMountainLeft: Double?
    var demoCutscene = false
    /// Demo an account that has only a weekly limit (no 5-hour window).
    var demoWeeklyOnly = false
    /// Demo tempo (`--tempo idle|low|high|veryHigh`).
    var demoPace: Pace.Level?
    /// When the cutscene began playing (demo recording); nil = loop it.
    var cutsceneStart: Date?
    /// Demo: someone from the tale at the left of the scene (`--visitor`).
    var demoVisitor: Visitor?
    /// When the plan or the family last changed (the wife comes to ask about it).
    private(set) var changedAt: Date?

    var demo: PetState?
    var demoCycle = false
    let bridgeURL: URL
    let scanner: LogScanner
    let codexReader = CodexReader(root: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"))
    let geminiReader = GeminiReader(root: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/tmp"))
    let budgets = BudgetClient()
    private let queue = DispatchQueue(label: "tokenpet.scan", qos: .utility)
    private var claude: Reading?
    private var accounts = Accounts.load()
    private var accountJustSwitched = false
    private var timer: Timer?

    init(bridgeURL: URL, logsRoot: URL) {
        self.bridgeURL = bridgeURL
        self.scanner = LogScanner(root: logsRoot)
    }

    func start() {
        StatusLineSetup.refreshInstalled(in: bridgeURL.deletingLastPathComponent())
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 5
    }

    func refresh() {
        if demo != nil || demoCycle { recompute(); return }
        checkForUpdate()   // at most once a day (Update.isDue); nothing in demos
        guard !scanning else { return }
        scanning = true
        queue.async { [self] in
            scanner.scan()
            codexReader.scan()
            geminiReader.scan()
            let b = Self.readBridge(bridgeURL)
            DispatchQueue.main.async { [self] in
                take(b)
                scanning = false
                mountain.absorb(allEvents)
                recompute()
                budgets.refresh(Array(family.roles.values)) { [weak self] in self?.recompute() }
            }
        }
    }

    /// Every local CLI's token events, oldest first: the mountain and the shovel speed.
    var allEvents: [LogScanner.Event] {
        (scanner.events + codexReader.events + geminiReader.events).sorted { $0.time < $1.time }
    }

    /// The latest reading for an AI; nil = nothing to read (Gemini, DeepSeek spend, no key or budget yet).
    func reading(_ p: Provider) -> Reading? {
        switch p {
        case .claude: return Limits.apply(Array(scanner.hits.values), to: claude, lastAnswer: scanner.events.last?.time, now: Date(),
                                          switchedAt: accounts.switchedAt)
        case .codex: return codexReader.reading
        case .gemini, .deepseek: return nil
        case .openai: return budgets.state[.openai].flatMap { st in st.spent.flatMap { Budget.reading(spent: $0, budget: openAIBudget, at: st.at) } }
        }
    }

    /// Blocking scan for CLI use (`--scan-report`).
    func scanNow() {
        scanner.scan()
        codexReader.scan()
        geminiReader.scan()
        take(Self.readBridge(bridgeURL))
        mountain.absorb(allEvents)
        recompute()
    }

    /// Fraction of the current mountain still standing (demo-aware).
    var mountainLeft: Double { demoMountainLeft ?? mountain.left }
    var cutsceneDue: Bool { demoCutscene || (demo == nil && !demoCycle && mountain.cutscenePending) }
    func finishCutscene() {
        cutsceneStart = nil
        if demoCutscene { demoCutscene = false; objectWillChange.send(); return }
        mountain.nextMountain()
    }
    /// The celebration was seen. The finale, if it waited for it, plays from the top.
    func dismissAward() {
        if !awards.isEmpty { awards.removeFirst() }
        if finaleDue { cutsceneStart = Date() }
    }

    /// Titles earned, 0...10: how many rewards the scene shows (LOGIC.md "Title rewards").
    var rewards: Int { Titles.rank(lifetime) + 1 }
    /// Demo: the #10 finale (`--demo finale`); a replay from the titles window.
    var demoFinale = false
    private(set) var finaleReplay = false
    /// The one-time #10 finale: after the mountain cutscene and the title's celebration, never in other demos.
    var finaleDue: Bool {
        demoFinale || finaleReplay
            || (demo == nil && !demoCycle && demoLifetime == nil && !cutsceneDue && awards.isEmpty && titles.finaleDue(lifetime))
    }
    func finishFinale() {
        cutsceneStart = nil
        if demoFinale || finaleReplay { demoFinale = false; finaleReplay = false; objectWillChange.send(); return }
        titles.finaleSeen = true
        titles.save()
    }
    func replayFinale() { finaleReplay = true; cutsceneStart = Date(); objectWillChange.send() }
    /// Demo: celebrate this award (stills and recordings).
    func demoAward(_ a: Award?) { awards = a.map { [$0] } ?? [] }
    /// Set by the app: opens the titles window.
    var openTitles: (() -> Void)?
    /// Set by the app: opens the first-run guide again (Settings).
    var openGuide: (() -> Void)?
    /// Opens the big scene in a window of its own (SceneWindow).
    var openWindow: (() -> Void)?

    /// A bridge reading, sorted by account (`Accounts`). A switch brings the wife to ask about it.
    private func take(_ b: Reading?) {
        let before = accounts.switchedAt
        claude = b.flatMap { accounts.take($0) }
        accounts.save()
        if let b, b != lastLogged {
            lastLogged = b
            // taken: the shown reading is at least this new; else the numbers were another account's
            let decision = accounts.switchedAt != before ? "switch" : (claude.map { $0.at >= b.at } ?? false) ? "taken" : "ignored"
            ReadingLog.append(ReadingLog.line(read: b, decision: decision, shown: claude, accounts: accounts))
        }
        guard accounts.switchedAt != before else { return }
        changedAt = Date()
        accountJustSwitched = true
    }
    private var lastLogged: Reading?
    /// The popover's last line: which Claude account (A, B, ... and its short hash) and when its numbers came.
    var accountLine: (letter: String?, id: String?, seen: Date?) { (accounts.letter, accounts.id.map { String($0.prefix(6)) }, accounts.seen) }
    /// "Account change detected" in the popover, for as long as the wife asks about it.
    var accountNote: Bool { accounts.switchedAt.map { Date().timeIntervalSince($0) < Visitors.afterChange } ?? false }

    static func readBridge(_ url: URL) -> Reading? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return Limits.bridge(data, fileDate: mtime)
    }

    func setDemo(_ s: PetState?) { demo = s; recompute() }

    /// Real night-time on this Mac: Grandpa yawns between digs.
    var night: Bool { let h = Calendar.current.component(.hour, from: Date()); return h >= 22 || h < 6 }

    /// Output tokens per minute right now (Claude Code, Codex and Gemini CLI logs).
    func liveRate(now: Date = Date()) -> Double {
        Pace.rate(allEvents.map { ($0.time, $0.output) }, now: now)
    }

    /// The animation clock. It runs at the tempo's speed and eases between speeds, so the pose never jumps.
    private var clockAnchor = (time: Date.timeIntervalSinceReferenceDate, phase: 0.0, speed: 1.0)
    var animSpeed: Double { clockAnchor.speed }
    func phase(at t: TimeInterval) -> Double {
        var a = clockAnchor
        let dt = t - a.time
        guard dt > 0 else { return a.phase }
        let next = Pace.ease(a.speed, to: tempoSpeed, dt: dt)
        a.phase += dt * (a.speed + next) / 2
        a.speed = next; a.time = t
        clockAnchor = a
        return a.phase
    }

    var tempo: Tempo { demoPace.map { $0 == .idle ? .idle : $0 == .veryHigh ? .sweating : .working } ?? pace.tempo }
    var tempoSpeed: Double { Pace.speed[demoPace ?? pace.level] ?? 1 }

    func recompute() {
        let now = Date()
        if let d = demo { snap = Self.demoSnapshot(d, now: now, weeklyOnly: demoWeeklyOnly, family: family); return }
        if demoCycle { return }
        pace.update(rate: liveRate(now: now), now: now)
        var others: [Role: Reading?] = [:]
        for (role, p) in family.roles where role != .grandpa { others[role] = reading(p) }
        snap = Logic.evaluate(main: family.roles[.grandpa].flatMap(reading), members: others, now: now)
        if demoLifetime == nil {
            let days = [scanner.events, codexReader.events, geminiReader.events].map { Titles.days($0.map(\.time)) }
            let new = titles.observe(TitleInputs(lifetime: lifetime, snap: snap, sourceDays: days, now: now))
            awards += new
            new.forEach { onAward?($0) }
        }
        // one notification when the limit is used up and one when it resets, even across a restart
        if snap.known, snap.resting != Prefs.store.bool(forKey: "limit.resting") {
            Prefs.store.set(snap.resting, forKey: "limit.resting")
            if notifyLimits && !accountJustSwitched { onLimit?(snap) }   // another account is not a used-up or reset limit
        }
        accountJustSwitched = false
        if let p = Visitors.plan(family, snap) {
            if let old = Prefs.store.string(forKey: "visitors.plan"), old != p { changedAt = now }
            Prefs.store.set(p, forKey: "visitors.plan")
        }
    }

    /// Who from the tale is in the scene right now (nobody during a cutscene).
    var visitor: Visitor? {
        if cutsceneDue || finaleDue { return nil }
        return demoVisitor ?? Visitors.who(snap, changedAt: changedAt, carried: 1 - mountainLeft, mountain: mountain.index, now: Date())
    }

    static func demoSnapshot(_ st: PetState, now: Date, weeklyOnly: Bool = false, family: Family = .standard) -> Snapshot {
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int = 0, daysAhead: Int = 0) -> Date {
            var d = cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
            if d <= now { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
            return cal.date(byAdding: .day, value: daysAhead, to: d) ?? d
        }
        var s = Snapshot(known: true, state: st)
        s.demo = true
        let kidPct: [PetState: Double] = [.lively: 18, .steady: 42, .straining: 66, .resting: 100, .morning: 4]
        // the demo is as honest as real data: Gemini and DeepSeek never report a limit
        for (role, p) in family.roles where role != .grandpa {
            let pct = role == .grandson ? kidPct[st] ?? 18 : role == .son ? 45 : 30
            switch p {
            case .gemini, .deepseek: s.members[role] = Member(reading: nil, fill: nil)
            case .openai: s.members[role] = Logic.member(Budget.reading(spent: pct, budget: 100, at: now), now: now)
            case .claude, .codex:
                s.members[role] = Member(reading: Reading(five: nil, week: Meter(pct: pct, resetsAt: at(10, daysAhead: 1)), at: now), fill: pct / 100)
            }
        }
        let weekly = at(9, daysAhead: 3)
        switch st {
        case .lively:    s.five = Meter(pct: 22, resetsAt: now.addingTimeInterval(2 * 3600 + 13 * 60)); s.week = Meter(pct: 21, resetsAt: weekly)
        case .steady:    s.five = Meter(pct: 48, resetsAt: now.addingTimeInterval(2 * 3600)); s.week = Meter(pct: 40, resetsAt: weekly)
        case .straining: s.five = Meter(pct: 91, resetsAt: now.addingTimeInterval(48 * 60)); s.week = Meter(pct: 63, resetsAt: weekly)
        case .resting:   let w = at(9); s.five = Meter(pct: 100, resetsAt: w); s.week = Meter(pct: 72, resetsAt: weekly)
                         s.resting = true; s.wakeAt = w
        case .morning:   s.five = Meter(pct: 0, resetsAt: nil); s.week = Meter(pct: 72, resetsAt: weekly); s.justReset = now
        }
        s.projected = s.five.flatMap { Logic.projection($0, window: Limits.fiveLength, now: now) }
        if weeklyOnly {
            // an account without a 5-hour window: the carrier is the week, today's share sets the pace
            let fills: [PetState: Double] = [.lively: 0.3, .steady: 0.8, .straining: 1.4, .resting: 1.6, .morning: 0]
            let dayStart = cal.date(bySettingHour: 4, minute: 0, second: 0, of: now).map { $0 > now ? $0.addingTimeInterval(-86400) : $0 } ?? now
            let f = fills[st] ?? 0.3
            s.daily = Daily(fill: f, dayStart: dayStart, dayEnd: dayStart.addingTimeInterval(86400))
            s.five = nil
            s.week = Meter(pct: [.lively: 31, .steady: 44, .straining: 58, .resting: 100, .morning: 61][st] ?? 31, resetsAt: weekly)
            s.projected = s.week.flatMap { Logic.projection($0, window: Limits.weekLength, now: now) }
            if st == .resting { s.wakeAt = weekly }
        }
        return s
    }

    /// `--allow-capture` (demo recording only): windows stay capturable without changing the saved setting.
    var captureAllowedForDemo = false

    // MARK: - Settings (UserDefaults domain of the app; `defaults delete <domain>` clears them)

    /// "auto" follows the system languages; "en", "ko", "ja" or "zh" pins it. Applied at once, no restart.
    @Published var language: String = Prefs.store.string(forKey: "language") ?? "auto" {
        didSet { Prefs.store.set(language, forKey: "language"); L.lang = L.resolve(language) }
    }
    /// Which AI each family member watches (Grandpa = the main one).
    @Published var family: Family = Family.load() {
        didSet { family.save(); recompute(); budgets.refresh(Array(family.roles.values)) { [weak self] in self?.recompute() } }
    }
    /// OpenAI: the monthly budget in USD that its meter fills against (0 = not set).
    @Published var openAIBudget: Double = Prefs.store.double(forKey: "budget.openai") {
        didSet { Prefs.store.set(openAIBudget, forKey: "budget.openai"); recompute() }
    }
    /// Saves (or with nil removes) an API key in the Keychain and asks again.
    func setKey(_ key: String?, for p: Provider) {
        Keychain.setKey(key, for: p)
        budgets.reset(p)
        budgets.refresh(Array(family.roles.values)) { [weak self] in self?.recompute() }
        recompute()
    }
    /// The menu-bar item: Grandpa on or off, and which number beside him (percent by default).
    @Published var barGrandpa: Bool = Prefs.store.object(forKey: "barGrandpa") as? Bool ?? true {
        didSet { Prefs.store.set(barGrandpa, forKey: "barGrandpa") }
    }
    @Published var barText: BarText = BarText(rawValue: Prefs.store.string(forKey: "barText") ?? "") ?? .percent {
        didSet { Prefs.store.set(barText.rawValue, forKey: "barText") }
    }
    /// The floating mini window: only while the menu-bar item is hidden (default), always, or never.
    @Published var miniMode: MiniMode = MiniMode(rawValue: Prefs.store.string(forKey: "miniWindow") ?? "") ?? .auto {
        didSet { Prefs.store.set(miniMode.rawValue, forKey: "miniWindow") }
    }

    /// Hide the title rewards in the background (sky, horizon, ground); Grandpa's gear stays. Off by default.
    @Published var hideProps: Bool = Prefs.store.bool(forKey: "rewards.hideProps") {
        didSet { Prefs.store.set(hideProps, forKey: "rewards.hideProps") }
    }

    /// A notification when Grandpa's limit is used up and when it resets. On by default.
    @Published var notifyLimits: Bool = Prefs.store.object(forKey: "limit.notify") as? Bool ?? true {
        didSet { Prefs.store.set(notifyLimits, forKey: "limit.notify") }
    }

    /// Open the Yugong window when the app starts (with "Open at login": at login). Off by default.
    @Published var windowAtLaunch: Bool = Prefs.store.bool(forKey: "sceneWindow.atLaunch") {
        didSet { Prefs.store.set(windowAtLaunch, forKey: "sceneWindow.atLaunch") }
    }

    /// Launch at login is opt-in only: the app never registers itself. Needs the .app bundle.
    var canLaunchAtLogin: Bool { Bundle.main.bundleIdentifier != nil }
    var launchAtLogin: SMAppService.Status { canLaunchAtLogin ? SMAppService.mainApp.status : .notRegistered }
    func setLaunchAtLogin(_ on: Bool) {
        do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
        catch { FileHandle.standardError.write("launch at login: \(error)\n".data(using: .utf8)!) }
        objectWillChange.send()
    }

    /// The update notice (Update.swift): on by default; off means the app never asks GitHub.
    @Published var checkUpdates: Bool = Prefs.store.object(forKey: "update.check") as? Bool ?? true {
        didSet { Prefs.store.set(checkUpdates, forKey: "update.check"); checkForUpdate() }
    }
    /// The newest release GitHub reported, kept so a restart shows it without asking again.
    @Published var latestVersion: String? = Prefs.store.string(forKey: "update.latest")
    @Published var skippedVersion: String? = Prefs.store.string(forKey: "update.skipped") {
        didSet { Prefs.store.set(skippedVersion, forKey: "update.skipped") }
    }
    @Published var updateStatus: Update.Status?
    /// Update clicked: working, or why it stopped (the old app is untouched).
    @Published var installStep: Update.Install?
    /// The popover never grows past the screen it opens on (set on each open, main.swift `show`).
    @Published var popoverMaxHeight: CGFloat = .infinity
    static func popoverMaxHeight(screen visible: CGFloat) -> CGFloat { max(200, visible - 40) }   // room for the arrow and margins

    /// Keep the pet and the numbers out of screen shares and recordings (default on).
    @Published var hideFromCapture: Bool = Prefs.store.object(forKey: "hideFromCapture") as? Bool ?? true {
        didSet { Prefs.store.set(hideFromCapture, forKey: "hideFromCapture") }
    }
}
