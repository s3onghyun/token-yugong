import Foundation
import TokenPetAssets

// The usage rules, written down in LOGIC.md. Pure functions of (readings, now): no files,
// no clock, no saved state, so every rule has a unit test (Tests/TokenPetTests).

/// One limit window: percent used (0...100) and when it resets.
struct Meter: Equatable {
    var pct: Double
    var resetsAt: Date?
}

/// One reading of the official limits. Either window may be absent.
struct Reading: Equatable {
    var five: Meter?
    var week: Meter?
    var at: Date            // when the tool reported these numbers
}

enum Limits {
    static let fiveLength: TimeInterval = 5 * 3600
    static let weekLength: TimeInterval = 7 * 86400

    /// The file bridge/statusline-bridge.sh writes: {"captured_at": epoch, "rate_limits": {five_hour, seven_day}}.
    /// nil = nothing usable (missing, corrupt, partial, or no window at all).
    static func bridge(_ data: Data, fileDate: Date) -> Reading? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = o["rate_limits"] as? [String: Any] else { return nil }
        let at = (o["captured_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? fileDate
        let r = Reading(five: meter(rl["five_hour"], "used_percentage"), week: meter(rl["seven_day"], "used_percentage"), at: at)
        return r.five == nil && r.week == nil ? nil : r
    }

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
        return Meter(pct: min(p, 100), resetsAt: (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) })
    }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
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
    var projected: Double?   // % this pace reaches by the reset
    var state: PetState = .lively
    var codex: Reading?
    var codexFill: Double?   // the grandson's basket
    var demo = false

    /// The limit that matters most: the 5-hour window, else the week. It is the carrier, the
    /// menu-bar number and the popover header.
    var headline: Meter? { five ?? week }
    /// Earth in Grandpa's carrier.
    var carrier: Double { headline.map { $0.pct / 100 } ?? 0 }
}

enum Logic {
    static let morningFor: TimeInterval = 300

    static func evaluate(claude: Reading?, codex: Reading?, now: Date) -> Snapshot {
        var s = Snapshot()
        if let c = codex {
            var r = c, ignored: [Date] = []
            r.five = roll(c.five, now, &ignored); r.week = roll(c.week, now, &ignored)
            s.codex = r
            s.codexFill = fill(five: r.five, week: r.week)
        }
        guard let c = claude else { return s }          // rule 1: no data -> "don't know"
        s.known = true
        s.captured = c.at
        var resets: [Date] = []
        s.five = roll(c.five, now, &resets)            // rule 2
        s.week = roll(c.week, now, &resets)
        let windows = [s.five, s.week].compactMap { $0 }
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

    static func fill(five: Meter?, week: Meter?) -> Double? { (five ?? week).map { $0.pct / 100 } }

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
        let top = [s.five, s.week].compactMap { $0?.pct }.max() ?? 0
        let pace = s.projected ?? top
        if top >= 80 || pace >= 110 { return .straining }
        if pace >= 75 { return .steady }
        return .lively
    }
}

// MARK: - Live pace (RunCat-style): how fast tokens are being generated on this Mac

/// Output tokens per minute over the last 3 minutes, from Claude Code and Codex logs, smoothed so
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
