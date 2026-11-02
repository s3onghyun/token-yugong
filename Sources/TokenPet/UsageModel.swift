import Foundation
import ServiceManagement
import TokenPetAssets

/// One settings domain however the app is started (`swift run` or the .app bundle), so the
/// mountain and the settings carry over. `defaults delete TokenPet` clears everything.
/// TOKENPET_PREFS names another domain (tests and demo recordings, so they leave yours alone).
enum Prefs {
    static let store = UserDefaults(suiteName: ProcessInfo.processInfo.environment["TOKENPET_PREFS"] ?? "TokenPet") ?? .standard
}

// MARK: - Codex CLI (local session logs; no network, no credentials)

/// Codex writes `rate_limits` into ~/.codex/sessions/**/rollout-*.jsonl on every `token_count`
/// event, with the response's token usage. Reads the newest 5 recent files, only when they change.
final class CodexReader {
    let root: URL
    private(set) var reading: Reading?
    private(set) var events: [(time: Date, tokens: Int)] = []   // output tokens, for the live pace
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
        var reading: Reading?, events: [(time: Date, tokens: Int)] = []
        for (u, _) in newest {
            guard let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.contains("\"token_count\"") {
                let data = Data(line.utf8)
                if let r = Limits.codex(data), r.at > (reading?.at ?? .distantPast) { reading = r }
                if let e = Self.output(data) { events.append(e) }
            }
        }
        self.reading = reading
        self.events = events.filter { $0.time > now.addingTimeInterval(-3600) }
    }

    static func output(_ line: Data) -> (time: Date, tokens: Int)? {
        guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let p = o["payload"] as? [String: Any], let info = p["info"] as? [String: Any],
              let last = info["last_token_usage"] as? [String: Any], let n = last["output_tokens"] as? Int,
              let t = (o["timestamp"] as? String).flatMap(Limits.iso.date(from:)) else { return nil }
        return (t, n)
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
    var name: String {
        switch index {
        case 0: return L.t("Mount Taihang", "태행산")
        case 1: return L.t("Mount Wangwu", "왕옥산")
        default: return L.t("Mountain #\(index + 1)", "\(index + 1)번째 산")
        }
    }
}

// MARK: - Model

final class UsageModel: ObservableObject {
    @Published private(set) var snap = Snapshot()
    @Published private(set) var pace = Pace()
    @Published private(set) var scanning = false
    @Published private(set) var mountain = MountainLedger.load()
    /// Demo override for the mountain (fraction left) and the cutscene.
    var demoMountainLeft: Double?
    var demoCutscene = false
    /// Demo an account that has only a weekly limit (no 5-hour window).
    var demoWeeklyOnly = false
    /// Demo tempo (`--tempo idle|low|high|veryHigh`).
    var demoPace: Pace.Level?
    /// When the cutscene began playing (demo recording); nil = loop it.
    var cutsceneStart: Date?

    var demo: PetState?
    var demoCycle = false
    let bridgeURL: URL
    let scanner: LogScanner
    let codexReader = CodexReader(root: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"))
    private let queue = DispatchQueue(label: "tokenpet.scan", qos: .utility)
    private var claude: Reading?
    private var timer: Timer?

    init(bridgeURL: URL, logsRoot: URL) {
        self.bridgeURL = bridgeURL
        self.scanner = LogScanner(root: logsRoot)
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 5
    }

    func refresh() {
        if demo != nil || demoCycle { recompute(); return }
        guard !scanning else { return }
        scanning = true
        queue.async { [self] in
            scanner.scan()
            codexReader.scan()
            let b = Self.readBridge(bridgeURL)
            DispatchQueue.main.async { [self] in
                claude = b
                scanning = false
                mountain.absorb(scanner.events)
                recompute()
            }
        }
    }

    /// Blocking scan for CLI use (`--scan-report`).
    func scanNow() {
        scanner.scan()
        codexReader.scan()
        claude = Self.readBridge(bridgeURL)
        mountain.absorb(scanner.events)
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
    /// Set by the app: opens the first-run guide again (Settings).
    var openGuide: (() -> Void)?

    static func readBridge(_ url: URL) -> Reading? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return Limits.bridge(data, fileDate: mtime)
    }

    func setDemo(_ s: PetState?) { demo = s; recompute() }

    /// Real night-time on this Mac: Grandpa yawns between digs.
    var night: Bool { let h = Calendar.current.component(.hour, from: Date()); return h >= 22 || h < 6 }

    /// Output tokens per minute right now (Claude Code + Codex logs).
    func liveRate(now: Date = Date()) -> Double {
        Pace.rate(scanner.events.map { ($0.time, $0.output) } + codexReader.events, now: now)
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
        if let d = demo { snap = Self.demoSnapshot(d, now: now, weeklyOnly: demoWeeklyOnly); return }
        if demoCycle { return }
        pace.update(rate: liveRate(now: now), now: now)
        snap = Logic.evaluate(claude: claude, codex: codexReader.reading, now: now)
    }

    static func demoSnapshot(_ st: PetState, now: Date, weeklyOnly: Bool = false) -> Snapshot {
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int = 0, daysAhead: Int = 0) -> Date {
            var d = cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
            if d <= now { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
            return cal.date(byAdding: .day, value: daysAhead, to: d) ?? d
        }
        var s = Snapshot(known: true, state: st)
        s.demo = true
        let codexPct: [PetState: Double] = [.lively: 18, .steady: 42, .straining: 66, .resting: 100, .morning: 4]
        s.codex = Reading(five: nil, week: Meter(pct: codexPct[st] ?? 18, resetsAt: at(10, daysAhead: 1)), at: now)
        let weekly = at(9, daysAhead: 3)
        switch st {
        case .lively:    s.five = Meter(pct: 22, resetsAt: now.addingTimeInterval(2 * 3600 + 13 * 60)); s.week = Meter(pct: 21, resetsAt: weekly)
        case .steady:    s.five = Meter(pct: 48, resetsAt: now.addingTimeInterval(2 * 3600)); s.week = Meter(pct: 40, resetsAt: weekly)
        case .straining: s.five = Meter(pct: 91, resetsAt: now.addingTimeInterval(48 * 60)); s.week = Meter(pct: 63, resetsAt: weekly)
        case .resting:   let w = at(9); s.five = Meter(pct: 100, resetsAt: w); s.week = Meter(pct: 72, resetsAt: weekly)
                         s.resting = true; s.wakeAt = w; s.restReason = "limit"
        case .morning:   s.five = Meter(pct: 0, resetsAt: nil); s.week = Meter(pct: 72, resetsAt: weekly); s.justReset = now
        }
        s.projected = s.five.flatMap { Logic.projection($0, window: Limits.fiveLength, now: now) }
        s.codexFill = (s.codex?.week?.pct ?? 0) / 100
        if weeklyOnly {
            // an account without a 5-hour window: the carrier is today's share of the week
            let fills: [PetState: Double] = [.lively: 0.3, .steady: 0.62, .straining: 0.9, .resting: 1.0, .morning: 0]
            let dayStart = cal.date(bySettingHour: 4, minute: 0, second: 0, of: now).map { $0 > now ? $0.addingTimeInterval(-86400) : $0 } ?? now
            let f = fills[st] ?? 0.3
            s.daily = Daily(fill: f, dayStart: dayStart, dayEnd: dayStart.addingTimeInterval(86400))
            s.five = nil
            s.week = Meter(pct: [.lively: 31, .steady: 44, .straining: 58, .resting: 61, .morning: 61][st] ?? 31, resetsAt: weekly)
            s.projected = s.week.flatMap { Logic.projection($0, window: Limits.weekLength, now: now) }
            if st == .resting { s.wakeAt = s.daily?.dayEnd; s.restReason = "daily" }
        }
        return s
    }

    /// `--allow-capture` (demo recording only): windows stay capturable without changing the saved setting.
    var captureAllowedForDemo = false

    // MARK: - Settings (UserDefaults domain of the app; `defaults delete <domain>` clears them)

    /// "auto" follows the system language; "ko" or "en" pins it.
    @Published var language: String = Prefs.store.string(forKey: "language") ?? "auto" {
        didSet { Prefs.store.set(language, forKey: "language"); L.korean = L.resolve(language) }
    }
    /// Show the grandson (Codex) in the scene and his meters.
    @Published var showCodex: Bool = Prefs.store.object(forKey: "showCodex") as? Bool ?? true {
        didSet { Prefs.store.set(showCodex, forKey: "showCodex") }
    }
    /// The floating mini window: only while the menu-bar item is hidden (default), always, or never.
    @Published var miniMode: MiniMode = MiniMode(rawValue: Prefs.store.string(forKey: "miniWindow") ?? "") ?? .auto {
        didSet { Prefs.store.set(miniMode.rawValue, forKey: "miniWindow") }
    }

    /// Launch at login is opt-in only: the app never registers itself. Needs the .app bundle.
    var canLaunchAtLogin: Bool { Bundle.main.bundleIdentifier != nil }
    var launchAtLogin: SMAppService.Status { canLaunchAtLogin ? SMAppService.mainApp.status : .notRegistered }
    func setLaunchAtLogin(_ on: Bool) {
        do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
        catch { FileHandle.standardError.write("launch at login: \(error)\n".data(using: .utf8)!) }
        objectWillChange.send()
    }

    /// Keep the pet and the numbers out of screen shares and recordings (default on).
    @Published var hideFromCapture: Bool = Prefs.store.object(forKey: "hideFromCapture") as? Bool ?? true {
        didSet { Prefs.store.set(hideFromCapture, forKey: "hideFromCapture") }
    }
}
