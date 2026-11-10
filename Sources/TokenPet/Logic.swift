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
    var account: String? = nil  // Claude: the signed-in account, hashed by the bridge (short hex); nil from older bridges
}

/// A family member other than Grandpa: his reading with passed resets applied, and his meter.
struct Member: Equatable {
    var reading: Reading?
    var fill: Double?       // nil = don't know
}

enum Limits {
    static let fiveLength: TimeInterval = 5 * 3600
    static let weekLength: TimeInterval = 7 * 86400

    /// The file bridge/statusline-bridge.sh writes: {"captured_at": epoch, "account": "<hash>", "rate_limits": {five_hour, seven_day}}.
    /// nil = nothing usable (missing, corrupt, partial, or no window at all). `account` is optional (older bridges).
    static func bridge(_ data: Data, fileDate: Date) -> Reading? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = o["rate_limits"] as? [String: Any] else { return nil }
        let at = (o["captured_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? fileDate
        let account = (o["account"] as? String).flatMap { a in
            (4...64).contains(a.count) && a.allSatisfy(\.isHexDigit) ? a.lowercased() : nil
        }
        let r = Reading(five: meter(rl["five_hour"], "used_percentage"), week: meter(rl["seven_day"], "used_percentage"), at: at, account: account)
        return r.five == nil && r.week == nil ? nil : r
    }

    /// Claude Desktop's local plan history records the same Max usage with compact names:
    /// `samples[].t` is milliseconds since epoch and `samples[].u.fh` is the 5-hour percentage.
    /// It deliberately does not supply a reset time.  Select the newest sample first: an omitted or
    /// null `fh` means the current source did not report the window, not that an older value is current.
    static func planUsageHistory(_ data: Data) -> Reading? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = root["samples"] as? [[String: Any]],
              let newest = samples.compactMap({ sample -> (Date, [String: Any])? in
                  guard let ms = (sample["t"] as? NSNumber)?.doubleValue, ms.isFinite, ms > 0,
                        let usage = sample["u"] as? [String: Any] else { return nil }
                  return (Date(timeIntervalSince1970: ms / 1_000), usage)
              }).max(by: { $0.0 < $1.0 }),
              let pct = (newest.1["fh"] as? NSNumber)?.doubleValue, pct.isFinite, pct >= 0 else { return nil }
        return Reading(five: Meter(pct: min(pct, 100), resetsAt: nil, resetUnavailable: true), week: nil, at: newest.0)
    }

    /// A status-line response remains the authority for the account and weekly reset.  Claude
    /// Desktop can fill only its missing five-hour percentage, and only when both local sources
    /// describe the same fresh moment.  This avoids reviving a stale `fh` after the API omits it.
    static func supplement(_ bridge: Reading?, with planHistory: Reading?, now: Date,
                           maximumSkew: TimeInterval = 5 * 60, maximumAge: TimeInterval = 10 * 60) -> Reading? {
        guard var bridge, bridge.five == nil, let history = planHistory, let five = history.five,
              abs(history.at.timeIntervalSince(bridge.at)) <= maximumSkew,
              now.timeIntervalSince(history.at) <= maximumAge else { return bridge }
        bridge.five = five
        return bridge
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

    /// Claude Code logs the rejected request when a limit is used up (`apiError: usage_limit_reached`).
    /// The status line never shows it: its numbers come from the last *successful* response, so they stop at 99.
    struct Hit: Equatable {
        var time: Date
        var week: Bool          // seven_day; else five_hour
        var resetsAt: Date
    }

    /// One Claude Code log line, decoded. nil unless it is a 5-hour or weekly limit rejection.
    static func hit(_ o: [String: Any]) -> Hit? {
        guard o["apiError"] as? String == "usage_limit_reached",
              let info = (o["apiErrorParams"] as? [String: Any])?["rate_limit_info"] as? [String: Any],
              let reset = (info["resetsAt"] as? NSNumber)?.doubleValue,
              let time = (o["timestamp"] as? String).flatMap(iso.date(from:)) else { return nil }
        switch info["rateLimitType"] as? String {
        case "five_hour": return Hit(time: time, week: false, resetsAt: Date(timeIntervalSince1970: reset))
        case "seven_day": return Hit(time: time, week: true, resetsAt: Date(timeIntervalSince1970: reset))
        default: return nil
        }
    }

    /// The status-line reading with the logged limit hits on top: a hit fills its window to 100% until
    /// it resets, unless Claude answered again after it (another account, extra usage) or the reading
    /// already shows a later window. Hits that reset more than `Logic.morningFor` ago are over.
    /// After an account switch (`Accounts`), the old account's hits are not the new one's: those logged
    /// before it, and later ones the newer reading shows as another window or (no such window) not at all.
    static func apply(_ hits: [Hit], to reading: Reading?, lastAnswer: Date?, now: Date, switchedAt: Date? = nil) -> Reading? {
        var r = reading
        for h in hits where h.resetsAt > now.addingTimeInterval(-Logic.morningFor) && (lastAnswer.map { $0 <= h.time } ?? true)
                            && (switchedAt.map { $0 < h.time } ?? true) {
            var x = r ?? Reading(five: nil, week: nil, at: h.time)
            let old = h.week ? x.week : x.five
            if let o = old?.resetsAt, o > h.resetsAt.addingTimeInterval(60) { continue }   // a newer window
            if let rd = reading {
                // another account's hit: the reading shows another window that has not reset (since a switch;
                // before one, only a reading taken after the hit tells), or after a switch no such window
                let shown = h.week ? rd.week : rd.five
                let other = shown?.resetsAt.map { !Accounts.same($0, h.resetsAt) && (switchedAt != nil ? $0 > now : rd.at > h.time) } ?? false
                if other || (shown?.resetsAt == nil && switchedAt != nil) { continue }   // none, or one that reset and is empty
            }
            let full = Meter(pct: 100, resetsAt: h.resetsAt)
            if h.week { x.week = full } else { x.five = full }
            x.at = max(x.at, h.time)
            r = x
        }
        return r
    }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
}

/// Which Claude account the bridge readings belong to (LOGIC.md "Another account"). Every Claude Code
/// session writes the one bridge file. After a /login the sessions use the new account, but an idle one
/// keeps the numbers of its last answer, from the old account, and writes them again whenever its
/// status line redraws. The bridge names the signed-in account (a hash); its numbers are told apart by
/// each account's weekly reset time. Older bridges name no account: then the weekly reset alone decides.
/// One account's sessions are merged window by window.
struct Accounts: Equatable, Codable {
    static let quiet: TimeInterval = 30 * 60   // the current account silent this long: the other one is back in use
    var week: Date?          // the current account's weekly reset
    var previous: Date?      // the account switched away from
    var switchedAt: Date?
    var seen: Date?          // the current account's newest reading
    var reading: Reading?    // its windows, merged
    var id: String?          // the signed-in account, as the bridge names it
    var weeks: [String: Date]? = nil   // each named account's weekly reset
    var ids: [String]? = nil           // named accounts in the order first seen: A, B, ...

    /// nil = an old account's reading and nothing of the current one since the app started.
    mutating func take(_ r: Reading) -> Reading? {
        if let t = r.account { return take(r, signedIn: t) }
        if let w = r.week?.resetsAt {
            if let cur = week, !Self.same(w, cur), !Self.next(w, after: cur, at: r.at) {
                // An older bridge can have no account hash. Its weekly-only payload is still
                // useful evidence: if a previous switch left no current reading, show it rather
                // than remaining permanently in the "don't know" state.
                if let p = previous, Self.same(w, p), let s = seen, r.at.timeIntervalSince(s) < Self.quiet,
                   let reading { return reading }
                previous = cur; switchedAt = r.at; reading = nil
            }
            week = w
        }
        return add(r)
    }

    /// The account in `~/.claude.json` is newer evidence than a status-line session.  A session
    /// created before `/login` keeps writing its old account's numbers, so never let that tagged
    /// payload replace the account currently signed in on this Mac.  Until a matching session
    /// replies, clear the old numbers rather than presenting them as the new account's usage.
    mutating func take(_ r: Reading, expectedAccount: String?) -> Reading? {
        guard let expectedAccount else { return take(r) }
        guard r.account == expectedAccount else {
            expect(expectedAccount, at: r.at)
            return reading
        }
        return take(r)
    }

    /// Select the account known from the local Claude login, with no claimed usage until its own
    /// status-line session replies.  `id` and `ids` are hashes only.
    mutating func expect(_ account: String, at: Date) {
        guard account != id else { return }
        if id != nil { previous = week; switchedAt = at }
        id = account; week = (weeks ?? [:])[account]; reading = nil; seen = nil
        if !(ids ?? []).contains(account) { ids = (ids ?? []) + [account] }
    }

    /// A reading from a bridge that names the signed-in account `t`.
    private mutating func take(_ r: Reading, signedIn t: String) -> Reading? {
        var known = weeks ?? [:]
        let remainsCurrent = t == id
        if t != id {   // a /login (or the first named reading: the account is not new, only its name)
            if id != nil { previous = week; switchedAt = r.at }
            id = t; week = known[t]; reading = nil; seen = nil
            if !(ids ?? []).contains(t) { ids = (ids ?? []) + [t] }
        }
        if let w = r.week?.resetsAt {
            // another account's week: an idle session still holding that account's numbers
            // Different accounts may legitimately share a weekly reset. Recover a known
            // current account only when it has no reading at all; otherwise the matching
            // reset is still the idle old-session redraw that must be ignored.
            let recoverCurrent = remainsCurrent && reading == nil
            if !recoverCurrent, known.contains(where: { $0.key != t && Self.same($0.value, w) }) { return reading }
            if !recoverCurrent, let cur = known[t], !Self.same(w, cur), !Self.next(w, after: cur, at: r.at) {
                // a week never seen for any account: numbers from before this app knew it, unless this one went quiet
                if let s = seen, r.at.timeIntervalSince(s) < Self.quiet { return reading }
                reading = nil
            }
            known[t] = w; weeks = known; week = w
        }
        return add(r)
    }

    private mutating func add(_ r: Reading) -> Reading? {
        reading = Self.merge(reading, r)
        seen = max(seen ?? r.at, r.at)
        return reading
    }

    /// "A", "B", ... for a named account; nil for an unnamed one (an older bridge).
    var letter: String? {
        guard let id, let i = ids?.firstIndex(of: id) else { return nil }
        return i < 26 ? String(UnicodeScalar(65 + i)!) : "#\(i + 1)"
    }

    /// A `/login` was seen, but its first status-line redraw belonged to an already-known account.
    /// Wait for a reply from the newly signed-in account instead of showing that old payload as new.
    var awaitingReading: Bool { id != nil && reading == nil }

    static func same(_ a: Date, _ b: Date) -> Bool { abs(a.timeIntervalSince(b)) <= 60 }
    /// `w` is the week after `cur`: `cur` has passed (as of `at`) and `w` is later.
    static func next(_ w: Date, after cur: Date, at: Date) -> Bool { cur <= at && w > cur }

    /// `n` is the newer reading. A window it lacks is kept while it has not reset; within one window the percent only grows.
    /// A window that has reset and that `n` lacks stays as a new, empty one: Claude Code drops a window from the status
    /// line once it resets, which does not make it an account without that window.
    static func merge(_ o: Reading?, _ n: Reading) -> Reading {
        guard let o else { return n }
        func window(_ a: Meter?, _ b: Meter?) -> Meter? {
            guard let a else { return b }
            guard let ra = a.resetsAt, ra > n.at else { return b ?? Meter(pct: 0, resetsAt: nil) }
            guard let b else { return a }
            guard let rb = b.resetsAt, same(ra, rb) else { return b }
            return Meter(pct: max(a.pct, b.pct), resetsAt: rb)
        }
        return Reading(five: window(o.five, n.five), week: window(o.week, n.week), at: max(o.at, n.at), month: n.month, account: n.account)
    }
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
