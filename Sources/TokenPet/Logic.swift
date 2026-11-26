import Foundation
import TokenPetAssets

// The usage rules, written down in LOGIC.md. Pure functions of (readings, now): no files,
// no clock, no saved state, so every rule has a unit test (Tests/TokenPetTests).

/// Decides whether the menu bar needs work without depending on AppKit.  An `NSStatusItem`
/// has one image shared by the system's menu-bar copies, so visibility is deliberately a
/// single "can anybody see it?" value rather than a display-specific setting.
enum MenuAnimationPolicy {
    /// A status item's variable length asks AppKit to measure and lay out the entire menu bar
    /// every time its image changes.  Grandpa's 20-point sprite and the widest label (`100%`)
    /// fit comfortably in this fixed slot, so animation only replaces layer contents.
    static let statusItemWidth: Double = 72

    static func isPaused(screensAsleep: Bool, sessionAway: Bool, statusItemVisible: Bool,
                         miniWindowVisible: Bool, measuring: Bool) -> Bool {
        screensAsleep || sessionAway || !(statusItemVisible || miniWindowVisible || measuring)
    }

    /// Low Power Mode holds the current pose and updates only the textual clock.  A static
    /// image is still useful, but never merits a frame timer or sprite lookup on each tick.
    static func shouldAnimate(lowPowerMode: Bool, showsImage: Bool, miniWindowVisible: Bool,
                              staging: Bool, measuring: Bool) -> Bool {
        !lowPowerMode && (showsImage || miniWindowVisible || staging || measuring)
    }

    static func staticRefreshInterval(showsClock: Bool) -> TimeInterval {
        showsClock ? 60 : 300
    }

    /// Low Power Mode needs one representative pose, not the first key frame.  Idle starts
    /// with Grandpa turned away to chat, which leaves only his pale beard and trousers visible
    /// at menu-bar size.  Hold the forward-facing idle key instead so the normal blue jacket
    /// and red sash remain legible on either menu-bar appearance.
    static func staticPoseTime(tempo: Tempo) -> TimeInterval {
        tempo == .idle ? 1.5 : 0
    }

    /// Keep text changes out of the frame loop.  This is deliberately separate from the image
    /// decision: frames are frequent, but a percentage or clock label usually is not.
    static func shouldUpdateText(previous: String, next: String) -> Bool { previous != next }
}

/// One limit window: percent used (0...100) and when it resets.
struct Meter: Equatable, Codable {
    var pct: Double
    var resetsAt: Date?
    /// Claude Desktop's compact plan history has a percentage but does not include a reset time.
    /// This is different from a window that Yugong knows has just reset.
    var resetUnavailable: Bool

    init(pct: Double, resetsAt: Date?, resetUnavailable: Bool = false) {
        self.pct = pct
        self.resetsAt = resetsAt
        self.resetUnavailable = resetUnavailable
    }

    private enum CodingKeys: String, CodingKey { case pct, resetsAt, resetUnavailable }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pct = try c.decode(Double.self, forKey: .pct)
        resetsAt = try c.decodeIfPresent(Date.self, forKey: .resetsAt)
        // Read the account state written by older Yugong releases too.
        resetUnavailable = try c.decodeIfPresent(Bool.self, forKey: .resetUnavailable) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pct, forKey: .pct)
        try c.encodeIfPresent(resetsAt, forKey: .resetsAt)
        if resetUnavailable { try c.encode(true, forKey: .resetUnavailable) }
    }
}

/// One reading of the official limits. Any window may be absent.
struct Reading: Equatable, Codable {
    var five: Meter?
    var week: Meter?
    var at: Date            // when the tool reported these numbers
    var month: Meter? = nil // a billed API: this month's spend against the budget
}

/// A family member other than Grandpa: his reading with passed resets applied, and his meter.
struct Member: Equatable {
    var reading: Reading?
    var fill: Double?       // nil = don't know
}

enum Limits {
    static let fiveLength: TimeInterval = 5 * 3600
    static let weekLength: TimeInterval = 7 * 86400

    /// One Codex rollout line whose payload carries `rate_limits` (primary/secondary windows).
    /// Only the two known window lengths are used: 300 min = 5-hour, 10080 min = weekly.
    static func codex(_ line: Data) -> Reading? {
        guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let p = o["payload"] as? [String: Any], let rl = p["rate_limits"] as? [String: Any],
              let at = (o["timestamp"] as? String).flatMap(iso.date(from:)) else { return nil }
        var r = Reading(five: nil, week: nil, at: at)
        for key in ["primary", "secondary"] {
            guard let w = rl[key] as? [String: Any], let m = meter(w, "used_percent") else { continue }
            switch (w["window_minutes"] as? NSNumber)?.intValue {
            case 300: r.five = m
            case 10080: r.week = m
            default: continue
            }
        }
        return r.five == nil && r.week == nil ? nil : r
    }

    static func meter(_ any: Any?, _ key: String) -> Meter? {
        guard let w = any as? [String: Any], let p = (w[key] as? NSNumber)?.doubleValue, p.isFinite, p >= 0 else { return nil }
        return Meter(pct: min(p, 100), resetsAt: epoch(w["resets_at"]))
    }

    /// The last instant `epoch` accepts: 2100-01-01T00:00:00Z.
    static let latestEpoch: TimeInterval = 4_102_444_800

    /// Epoch seconds from a local file (limits.json, a Claude Code log) as a date; nil unless finite and
    /// within 1970…2100, so an absurd value is ignored instead of travelling on to a whole-number conversion.
    static func epoch(_ any: Any?) -> Date? {
        guard let s = (any as? NSNumber)?.doubleValue, s.isFinite, (0...latestEpoch).contains(s) else { return nil }
        return Date(timeIntervalSince1970: s)
    }

    /// A whole number of seconds or minutes to show or print: clamped first, so it never traps.
    static func whole(_ x: Double) -> Int { x.isFinite ? Int(min(max(x, -1e15), 1e15)) : 0 }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
}

/// Which reader a row belongs to: Codex's one local reader, or a Claude Code profile (LOGIC.md "Accounts").
/// A profile holds one login and is asked on its own, so its readings are never another account's.
struct AccountKey: Hashable, Codable {
    let value: String

    static let local = AccountKey(value: "local")
    static let claudeDefault = AccountKey(value: "claude:default")
    static func claude(dir: String?) -> AccountKey { dir.map { AccountKey(value: "claude:dir:" + $0) } ?? claudeDefault }

    var isClaude: Bool { value.hasPrefix("claude:") }
    /// The CLAUDE_CONFIG_DIR folder; nil for the default profile (~/.claude) and for Codex.
    var dir: String? { value.hasPrefix("claude:dir:") ? String(value.dropFirst("claude:dir:".count)) : nil }
}

/// What one profile said the last time it was asked.
struct ClaudeAnswer: Equatable, Codable {
    /// nil = the last answer could not be read: don't know (never an older number).
    var reading: Reading?
    /// The profile's signed-in email when it answered; names the row.
    var login: String?
    var at: Date
}

/// The Claude profiles (the default one and the CLAUDE_CONFIG_DIR folders the user added), their last answers,
/// when each may be asked again, the one Grandpa watches, and the user's nicknames. All local.
struct ClaudeAccounts: Equatable, Codable {
    private(set) var dirs: [String] = []
    private(set) var selected = AccountKey.claudeDefault
    private var answers: [String: ClaudeAnswer] = [:]
    private var asks: [String: ClaudeAsk] = [:]
    private var nicknames: [String: String] = [:]

    var keys: [AccountKey] { [.claudeDefault] + dirs.map { AccountKey.claude(dir: $0) } }

    /// Adds a CLAUDE_CONFIG_DIR folder. nil when it is empty, already there, or the default ~/.claude.
    @discardableResult mutating func add(dir: String, home: URL) -> AccountKey? {
        guard dir.hasPrefix("/") else { return nil }   // a relative path would be the app's own folder
        let d = URL(fileURLWithPath: dir).standardizedFileURL.path
        guard d != "/", d != home.appendingPathComponent(".claude").standardizedFileURL.path,
              !dirs.contains(d) else { return nil }
        dirs.append(d)
        return .claude(dir: d)
    }

    /// Removes an added profile with everything about it. The default profile stays.
    mutating func remove(_ key: AccountKey) {
        guard let d = key.dir else { return }
        dirs.removeAll { $0 == d }
        answers.removeValue(forKey: key.value); asks.removeValue(forKey: key.value); nicknames.removeValue(forKey: key.value)
        if selected == key { selected = .claudeDefault }
    }

    mutating func select(_ key: AccountKey) { if keys.contains(key) { selected = key } }

    func ask(_ key: AccountKey) -> ClaudeAsk { asks[key.value] ?? ClaudeAsk() }
    func answer(_ key: AccountKey) -> ClaudeAnswer? { answers[key.value] }
    var selectedReading: Reading? { answers[selected.value]?.reading }

    /// Opening the popover lets the background refresh ask a stopped profile again (once its hold is over).
    mutating func popoverOpened() { for k in asks.keys { asks[k]?.stopped = false } }

    /// One answer for one profile. Fresh rows replace the reading. An unreadable answer means don't know.
    /// No fresh rows (rate limited, signed out) keeps the last reading with its age, but only while the
    /// profile is still signed in to the account that gave it: a number is never shown under another login.
    mutating func take(_ answer: ClaudeUsage.Answer, login: String?, for key: AccountKey, now: Date) {
        guard keys.contains(key) else { return }
        var ask = self.ask(key)
        ask.record(answer, now: now)
        asks[key.value] = ask
        let old = answers[key.value]
        switch answer {
        case .limits(let r): answers[key.value] = ClaudeAnswer(reading: r, login: login, at: now)
        case .unreadable: answers[key.value] = ClaudeAnswer(reading: nil, login: login, at: now)
        case .noLimits:
            let same = old.map { $0.login == login } ?? false
            answers[key.value] = ClaudeAnswer(reading: same ? old?.reading : nil, login: login, at: old.map { same ? $0.at : now } ?? now)
        }
    }

    func nickname(for key: AccountKey) -> String? { nicknames[key.value] }

    mutating func setNickname(_ nickname: String, for key: AccountKey) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { nicknames.removeValue(forKey: key.value) } else { nicknames[key.value] = trimmed }
    }

    func rows(codex: Reading?) -> [AccountRow] {
        keys.map { key in
            let a = answers[key.value]
            return AccountRow(key: key, reading: a?.reading, login: a?.login, answeredAt: a?.at, nickname: nicknames[key.value],
                              selected: selected == key, heldUntil: self.ask(key).heldUntil)
        } + (codex.map { [AccountRow(key: .local, reading: $0, login: nil, answeredAt: $0.at, nickname: nicknames[AccountKey.local.value],
                                     selected: false, heldUntil: nil)] } ?? [])
    }
}

struct AccountRow: Identifiable, Equatable {
    let key: AccountKey
    let reading: Reading?
    let login: String?
    let answeredAt: Date?
    let nickname: String?
    let selected: Bool
    let heldUntil: Date?
    var id: String { key.value }
}

/// Weekly-only accounts: the week (counted back from its reset) is 7 equal days, and by the end
/// of day d (0...6) the fair use is (d+1)/7 of the week. fill = (used - d/7) / (1/7):
/// 0 = nothing of today's share used yet (unused days carry over), 1 = today's share used up.
/// It only sets the pace; it never makes him rest.
struct Daily: Equatable {
    static let share = 100.0 / 7
    var fill: Double
    var dayStart: Date
    var dayEnd: Date

    static func of(_ w: Meter, resetsAt r: Date, now: Date) -> Daily {
        let start = r.addingTimeInterval(-Limits.weekLength)
        let d = max(0, min(6, floor(now.timeIntervalSince(start) / 86400)))
        let dayStart = start.addingTimeInterval(d * 86400)
        return Daily(fill: max(0, (w.pct - d * share) / share), dayStart: dayStart, dayEnd: dayStart.addingTimeInterval(86400))
    }
}

/// What the UI renders.
struct Snapshot {
    var known = false        // false: no usable Claude reading, so the pet says it does not know
    var captured: Date?
    var five: Meter?
    var week: Meter?
    var daily: Daily?        // set when there is a weekly window but no 5-hour window
    var resting = false      // a window is at 100%
    var wakeAt: Date?        // nil while resting = the reset time is not known
    var justReset: Date?
    var weekStart: Date?     // when the current weekly window began
    var projected: Double?   // % this pace reaches by the reset
    var state: PetState = .lively
    var month: Meter?
    var members: [Role: Member] = [:]   // the rest of the family (Settings › Family)
    var demo = false

    /// The limit that matters most: the 5-hour window, else the week, else the month (a billed API).
    /// It is the carrier, the menu-bar number and the popover header.
    var headline: Meter? { five ?? week ?? month }
    /// Earth in Grandpa's carrier.
    var carrier: Double { headline.map { $0.pct / 100 } ?? 0 }
}

enum Logic {
    static let morningFor: TimeInterval = 300

    /// `main` is Grandpa's AI; `members` the others in the family (nil = assigned, nothing to read).
    static func evaluate(main: Reading?, members: [Role: Reading?] = [:], now: Date) -> Snapshot {
        var s = Snapshot()
        s.members = members.mapValues { member($0, now: now) }
        guard let c = main else { return s }            // rule 1: no data -> "don't know"
        s.known = true
        s.captured = c.at
        var resets: [Date] = []
        if let r = c.week?.resetsAt { s.weekStart = r <= now ? r : r.addingTimeInterval(-Limits.weekLength) }
        s.five = roll(c.five, now, &resets)            // rule 2
        s.week = roll(c.week, now, &resets)
        s.month = roll(c.month, now, &resets)
        let windows = [s.five, s.week, s.month].compactMap { $0 }
        let full = windows.filter { $0.pct >= 100 }     // rule 3
        if !full.isEmpty {
            s.resting = true
            s.wakeAt = full.contains { $0.resetsAt == nil } ? nil : full.compactMap(\.resetsAt).max()
        }
        if s.five == nil, let w = s.week, let r = w.resetsAt {   // rule 4
            let d = Daily.of(w, resetsAt: r, now: now)
            s.daily = d
            resets.append(d.dayStart)
        }
        s.justReset = resets.filter { now >= $0 && now.timeIntervalSince($0) < morningFor }.max()   // rule 5
        s.projected = [s.five.flatMap { projection($0, window: Limits.fiveLength, now: now) },
                       s.week.flatMap { projection($0, window: Limits.weekLength, now: now) }].compactMap { $0 }.max()
        s.state = state(s)
        return s
    }

    /// A window whose reset time has passed is a new, empty window; its next reset is unknown until the tool reports again.
    static func roll(_ m: Meter?, _ now: Date, _ resets: inout [Date]) -> Meter? {
        guard var m else { return nil }
        if let r = m.resetsAt, r <= now { resets.append(r); m.pct = 0; m.resetsAt = nil }
        return m
    }

    /// The others' meters: the same windows and rule 2, filled by the 5-hour, else weekly, else monthly %.
    static func member(_ r: Reading?, now: Date) -> Member {
        guard var r else { return Member(reading: nil, fill: nil) }
        var ignored: [Date] = []
        r.five = roll(r.five, now, &ignored); r.week = roll(r.week, now, &ignored); r.month = roll(r.month, now, &ignored)
        return Member(reading: r, fill: (r.five ?? r.week ?? r.month).map { $0.pct / 100 })
    }

    /// Where this pace lands by the reset: used % / share of the window gone by (at least 12%, so a
    /// window that just started is not judged on a few minutes).
    static func projection(_ m: Meter, window: TimeInterval, now: Date) -> Double? {
        guard let r = m.resetsAt, r > now else { return nil }
        let elapsed = 1 - r.timeIntervalSince(now) / window
        return m.pct / max(0.12, min(1, elapsed))
    }

    /// Rule 6, after resting and morning.
    static func state(_ s: Snapshot) -> PetState {
        if s.resting { return .resting }
        if s.justReset != nil { return .morning }
        if let d = s.daily {           // weekly-only: today's share is the pace
            return d.fill >= 1 ? .straining : d.fill >= 0.75 ? .steady : .lively
        }
        let top = [s.five, s.week, s.month].compactMap { $0?.pct }.max() ?? 0
        let pace = s.projected ?? top
        if top >= 80 || pace >= 110 { return .straining }
        if pace >= 75 { return .steady }
        return .lively
    }
}

// MARK: - Visitors from the tale (LOGIC.md "Visitors")

enum Visitors {
    static let afterChange: TimeInterval = 600        // the wife asks for 10 minutes after the plan or the family changes
    static let newWeek: TimeInterval = 6 * 3600       // and for the first 6 hours of a new week

    /// Who stands at the left of the scene. Zhisou while Grandpa's limit is used up; otherwise the wife
    /// after a change or at a new week, doubting until half the first mountain is gone, cheering after.
    static func who(_ s: Snapshot, changedAt: Date?, carried: Double, mountain: Int, now: Date) -> Visitor? {
        guard s.known else { return nil }
        if s.resting { return .zhisou }
        func within(_ d: Date?, _ span: TimeInterval) -> Bool { d.map { now >= $0 && now.timeIntervalSince($0) < span } ?? false }
        guard within(changedAt, afterChange) || within(s.weekStart, newWeek) else { return nil }
        return mountain > 0 || carried >= 0.5 ? .wifeCheering : .wifeDoubting
    }

    /// What the wife's question is about: who watches which AI, and which windows Grandpa's AI has.
    /// nil while there is no reading (a missing reading is not a change of plan).
    static func plan(_ f: Family, _ s: Snapshot) -> String? {
        guard s.known else { return nil }
        let roles = Role.allCases.compactMap { r in f.roles[r].map { "\(r.rawValue)=\($0.rawValue)" } }
        return (roles + [s.five != nil ? "5h" : "", s.week != nil ? "week" : "", s.month != nil ? "month" : ""]).joined(separator: ",")
    }

    /// (the visitor's line, Grandpa's answer)
    static func lines(_ v: Visitor) -> (String, String) {
        switch v {
        case .wifeDoubting:
            return (L.t("Grandma\nAnd where will you dump all that earth?",
                        "할머니\n그 흙은 다 어디다 버리려고?",
                        "おばあさん\nその土、いったいどこに捨てるつもり？",
                        "奶奶\n这么多土石，往哪儿放呀？"),
                    L.t("Off the tail of the Bohai Sea, ho ho!", "발해 끝에 버리면 되지, 허허!", "渤海の果てに捨てればよい、ほっほっ！", "投到渤海的尽头去，呵呵！"))
        case .wifeCheering:
            return (L.t("Grandma\nIt really is shrinking! Go on, dear!",
                        "할머니\n어머, 정말 줄었네! 힘내요, 영감!",
                        "おばあさん\nまあ、本当に減ってる！がんばって、あなた！",
                        "奶奶\n哎呀，真的变小了！老头子，加油！"),
                    L.t("See? One shovel at a time.", "거봐요, 한 삽씩이면 된다니까.", "ほれ見なさい、ひとすくいずつじゃ。", "看吧，一锹一锹来就行。"))
        case .zhisou:
            return (L.t("Zhisou\nTold you so, ho ho! Not one blade of grass moved.",
                        "지수 영감\n거봐라, 허허! 풀 한 포기도 못 뽑겠구먼.",
                        "智叟\nほれ見たことか、ほっほっ！草一本動かせんわい。",
                        "智叟\n早说了吧，呵呵！连一根草都动不了。"),
                    L.t("Sons, then grandsons, on and on for ever. The mountain won't grow!",
                        "아들, 손자, 자자손손 끝이 없지. 산은 더 자라지 않는다네!",
                        "子から孫へ、子々孫々尽きることはない。山はこれ以上高くならんのじゃ！",
                        "子又生孙，孙又生子，子子孙孙无穷尽。山可不会再长高！"))
        }
    }
}

// MARK: - Live pace (RunCat-style): how fast tokens are being generated on this Mac

/// Output tokens per minute over the last 3 minutes, from Claude Code, Codex and Gemini CLI logs, smoothed so
/// the shovel speeds up and slows down gently and never flickers between levels.
struct Pace {
    enum Level: Int, Comparable, CaseIterable {
        case idle, low, high, veryHigh
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }
    static let window: TimeInterval = 180
    static let tau: TimeInterval = 60                 // smoothing time constant
    static let bounds: [Double] = [50, 2000, 8000]    // tokens/min where low, high, very high start
    static let dropBelow = 0.8                        // to fall back a level the rate must drop 20% under its bound
    static let speed: [Level: Double] = [.idle: 1, .low: 0.6, .high: 1, .veryHigh: 1.5]

    private(set) var smoothed = 0.0
    private(set) var level = Level.idle
    private var last: Date?

    /// Output tokens per minute in (now - window, now]. Events stamped in the future are ignored.
    static func rate(_ events: [(time: Date, tokens: Int)], now: Date) -> Double {
        let from = now.addingTimeInterval(-window)
        return Double(events.filter { $0.time > from && $0.time <= now }.reduce(0) { $0 + $1.tokens }) / (window / 60)
    }

    mutating func update(rate: Double, now: Date) {
        if let last {
            let dt = max(0, now.timeIntervalSince(last))     // a clock moved back does not count as time
            smoothed += (rate - smoothed) * (1 - exp(-dt / Self.tau))
        } else {
            smoothed = rate
        }
        last = now
        var l = level
        while l < .veryHigh, smoothed >= Self.bounds[l.rawValue] { l = Level(rawValue: l.rawValue + 1)! }
        while l > .idle, smoothed < Self.bounds[l.rawValue - 1] * Self.dropBelow { l = Level(rawValue: l.rawValue - 1)! }
        level = l
    }

    var tempo: Tempo { level == .idle ? .idle : level == .veryHigh ? .sweating : .working }

    /// The animation clock eases toward the level's speed (time constant 1.5 s).
    static func ease(_ current: Double, to target: Double, dt: Double) -> Double {
        current + (target - current) * (1 - exp(-max(0, dt) / 1.5))
    }
}
