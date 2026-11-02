import Foundation
import TokenPetAssets

// MARK: - Local Claude Code log scanner (no network, no credentials)

/// Incrementally reads ~/.claude/projects/**/*.jsonl. Only assistant lines are decoded:
/// token counts (message.usage) and Claude Code's own "limit reached · resets <time>" errors.
final class LogScanner {
    struct Event { let time: Date; let tokens: Int }
    struct LimitHit { let time: Date; let wake: Date?; let kind: String }

    let root: URL
    private var offsets: [String: UInt64] = [:]
    private var seen = Set<String>()
    private(set) var events: [Event] = []
    private(set) var hits: [LimitHit] = []
    private(set) var lastScanSeconds: Double = 0
    private(set) var bytesRead: UInt64 = 0

    init(root: URL) { self.root = root }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let assistantNeedle = Array(#""type":"assistant""#.utf8)
    private static let usageNeedle = Array(#""usage":{"#.utf8)
    private static let limitNeedles = [Array("usage_limit_reached".utf8), Array(#""error":"rate_limit""#.utf8)]

    func scan(now: Date = Date()) {
        let started = Date()
        let cutoff = now.addingTimeInterval(-7 * 86400)
        let fm = FileManager.default
        guard let it = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                     options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in it where url.pathExtension == "jsonl" {
            guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mtime = v.contentModificationDate, mtime >= cutoff, let size = v.fileSize else { continue }
            var off = offsets[url.path] ?? 0
            if UInt64(size) < off { off = 0 }
            if UInt64(size) == off { continue }
            offsets[url.path] = read(url, from: off)
        }
        events.removeAll { $0.time < cutoff }
        events.sort { $0.time < $1.time }
        hits.sort { $0.time < $1.time }
        if hits.count > 50 { hits.removeFirst(hits.count - 50) }
        lastScanSeconds = Date().timeIntervalSince(started)
    }

    /// Returns the offset just past the last complete line consumed.
    private func read(_ url: URL, from start: UInt64) -> UInt64 {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return start }
        defer { try? fh.close() }
        do { try fh.seek(toOffset: start) } catch { return start }
        var consumed = start
        var carry = Data()
        while true {
            let more: Bool = autoreleasepool {
            guard let chunk = try? fh.read(upToCount: 8 << 20), !chunk.isEmpty else { return false }
            bytesRead += UInt64(chunk.count)
            carry.append(chunk)
            var lineStart = carry.startIndex
            carry.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
                let base = buf.baseAddress!
                var i = 0
                let n = buf.count
                while i < n {
                    guard let nl = memchr(base + i, 0x0A, n - i) else { break }
                    let end = base.distance(to: UnsafeRawPointer(nl))
                    handleLine(UnsafeRawBufferPointer(start: base + i, count: end - i))
                    i = end + 1
                }
                lineStart = carry.startIndex + i
            }
            consumed += UInt64(lineStart - carry.startIndex)
            carry = carry.subdata(in: lineStart..<carry.endIndex)
            return true
            }
            if !more { break }
        }
        return consumed
    }

    private static func contains(_ line: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        guard line.count >= needle.count, let base = line.baseAddress else { return false }
        return needle.withUnsafeBytes { memmem(base, line.count, $0.baseAddress!, needle.count) != nil }
    }

    private func handleLine(_ line: UnsafeRawBufferPointer) {
        guard Self.contains(line, Self.assistantNeedle) else { return }
        let isLimit = Self.limitNeedles.contains { Self.contains(line, $0) }
        guard isLimit || Self.contains(line, Self.usageNeedle) else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let ts = obj["timestamp"] as? String, let time = Self.iso.date(from: ts) else { return }
        let msg = obj["message"] as? [String: Any]
        if (obj["isApiErrorMessage"] as? Bool) == true {
            // Only Claude Code's own limit error counts, never a transcript that merely mentions it.
            guard obj["error"] as? String == "rate_limit" || obj["apiError"] as? String == "usage_limit_reached" else { return }
            let text = ((msg?["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: " ")) ?? ""
            let lower = text.lowercased()
            let kind = lower.contains("weekly") ? "weekly" : (lower.contains("5-hour") || lower.contains("session")) ? "5-hour" : "limit"
            hits.append(LimitHit(time: time, wake: Self.parseReset(text, after: time), kind: kind))
            return
        }
        guard let usage = msg?["usage"] as? [String: Any] else { return }
        let key = (msg?["id"] as? String ?? "") + "|" + (obj["requestId"] as? String ?? ts)
        guard seen.insert(key).inserted else { return }
        let tokens = (usage["input_tokens"] as? Int ?? 0) + (usage["output_tokens"] as? Int ?? 0)
            + (usage["cache_creation_input_tokens"] as? Int ?? 0)
        events.append(Event(time: time, tokens: tokens))
    }

    /// Parses Claude Code's "resets 10pm (Asia/Seoul)" / "resets Nov 3, 9:30am (Asia/Seoul)".
    static func parseReset(_ text: String, after: Date) -> Date? {
        let pattern = #"resets\s+(?:([A-Z][a-z]{2})\s+(\d{1,2}),?\s+(?:at\s+)?)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)(?:\s*\(([^)]+)\))?"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func g(_ i: Int) -> String? { Range(m.range(at: i), in: text).map { String(text[$0]) } }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = g(6).flatMap(TimeZone.init(identifier:)) ?? .current
        var hour = Int(g(3) ?? "") ?? 0
        let minute = Int(g(4) ?? "") ?? 0
        let pm = g(5)?.lowercased() == "pm"
        if hour == 12 { hour = 0 }
        if pm { hour += 12 }
        var dc = cal.dateComponents([.year, .month, .day], from: after)
        dc.hour = hour; dc.minute = minute; dc.second = 0
        if let mon = g(1), let day = Int(g(2) ?? "") {
            let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
            if let idx = months.firstIndex(of: mon.lowercased()) { dc.month = idx + 1; dc.day = day }
            guard var d = cal.date(from: dc) else { return nil }
            if d < after, let n = cal.date(byAdding: .year, value: 1, to: d) { d = n }
            return d
        }
        guard var d = cal.date(from: dc) else { return nil }
        if d <= after, let n = cal.date(byAdding: .day, value: 1, to: d) { d = n }
        return d
    }
}

// MARK: - Codex CLI (local session logs; no network, no credentials)

/// Codex writes `rate_limits` into ~/.codex/sessions/**/rollout-*.jsonl on every `token_count`
/// event: windows carry used_percent, window_minutes (300 = 5h, 10080 = weekly) and resets_at.
enum CodexReader {
    struct Reading { let five: Meter?; let week: Meter?; let at: Date }

    static func read(root: URL, now: Date = Date()) -> Reading? {
        let fm = FileManager.default
        guard let it = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        let cutoff = now.addingTimeInterval(-8 * 86400)
        var files: [(URL, Date)] = []
        for case let u as URL in it where u.pathExtension == "jsonl" {
            if let m = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, m >= cutoff { files.append((u, m)) }
        }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for (u, _) in files.sorted(by: { $0.1 > $1.1 }).prefix(5) {
            guard let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
                guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let p = o["payload"] as? [String: Any], let rl = p["rate_limits"] as? [String: Any] else { continue }
                let at = (o["timestamp"] as? String).flatMap(iso.date(from:)) ?? now
                var five: Meter?, week: Meter?
                for key in ["primary", "secondary"] {
                    guard let w = rl[key] as? [String: Any], let pct = (w["used_percent"] as? NSNumber)?.doubleValue else { continue }
                    var reset = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                    var used = pct
                    if let r = reset, r <= now { used = 0; reset = nil }      // window rolled over since
                    let m = Meter(pct: used, resetsAt: reset)
                    if (w["window_minutes"] as? Int ?? 0) <= 300 { five = m } else { week = m }
                }
                if five != nil || week != nil { return Reading(five: five, week: week, at: at) }
            }
        }
        return nil
    }
}

// MARK: - Snapshot the UI renders

struct Meter {
    var pct: Double          // 0...100+ (vs official limit, or vs user budget)
    var resetsAt: Date?
    var tokens: Int?         // measured mode only
    var rolling = false      // measured weekly has no fixed reset
}

enum DataSource: Equatable {
    case official(captured: Date)   // Claude Code status line `rate_limits`
    case measured                   // local logs vs user-set budget
    case demo
}

struct Snapshot {
    var five: Meter?
    var week: Meter?
    var source: DataSource = .measured
    var sleepUntil: Date?
    var sleepReason: String?
    var justReset: Date?
    var codex: CodexReader.Reading?
    var learned5h: Int?      // tokens in the 5h block when Claude Code last said "session limit"
    var projected: Double?   // % of the limit this pace reaches by the reset (tokens per hour vs time left)
    var state: PetState = .lively

    /// Set when the account has a weekly limit but no 5-hour window (e.g. verified Ultra).
    var daily: Daily?
    /// The grandson's basket: Codex 5-hour usage, or today's share of its weekly limit.
    var codexFill: Double?

    /// Earth in Grandpa's carrier: the 5-hour window, or today's share of the week when there is no 5-hour window.
    var carrier: Double { daily?.fill ?? ((five ?? week)?.pct ?? 0) / 100 }
}

/// Today's fair share of a weekly limit: the week (from its reset time) split into 7 equal days.
/// fill 1.0 = today's 1/7 is used up, so Grandpa rests until the next day starts.
struct Daily {
    var fill: Double          // used today / today's share
    var usedToday: Double     // percentage points of the weekly limit used since the day began
    var share: Double         // 100/7
    var dayStart: Date
    var dayEnd: Date
    var estimated: Bool       // the day's starting point was estimated (first seen late in the day)

    static func of(_ w: Meter, resetsAt r: Date, now: Date, key: String?) -> Daily {
        let start = r.addingTimeInterval(-7 * 86400)
        let d = max(0, min(6, floor(now.timeIntervalSince(start) / 86400)))
        let dayStart = start.addingTimeInterval(d * 86400)
        let share = 100.0 / 7
        let ud = UserDefaults.standard
        var base: Double, est = false
        if let key, ud.double(forKey: key + ".dayStart") == dayStart.timeIntervalSince1970 {
            base = ud.double(forKey: key + ".base"); est = ud.bool(forKey: key + ".estimated")
        } else {
            // seen early in the day: start from here; otherwise assume the week was on pace until today
            if now.timeIntervalSince(dayStart) < 3600 { base = w.pct } else { base = min(w.pct, d * share); est = d > 0 }
            if let key {
                ud.set(dayStart.timeIntervalSince1970, forKey: key + ".dayStart")
                ud.set(base, forKey: key + ".base"); ud.set(est, forKey: key + ".estimated")
            }
        }
        let used = max(0, w.pct - min(base, w.pct))
        return Daily(fill: used / share, usedToday: used, share: share, dayStart: dayStart,
                     dayEnd: dayStart.addingTimeInterval(86400), estimated: est)
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

    static func load() -> MountainLedger {
        let d = UserDefaults.standard
        return MountainLedger(tokens: d.double(forKey: "mountain.tokens"),
                              through: (d.object(forKey: "mountain.through") as? Double).map(Date.init(timeIntervalSince1970:)),
                              index: d.integer(forKey: "mountain.index"),
                              cutscenePending: d.bool(forKey: "mountain.cutscene"),
                              size: (d.object(forKey: "mountain.size") as? Double) ?? defaultSize)
    }

    func save() {
        let d = UserDefaults.standard
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
    @Published var style: CharacterStyle   // saved only by an explicit pick (see PopoverView)
    /// nil = use the learned limit (or the fallback) instead of a hand-set budget.
    @Published var budget5h: Double? {
        didSet { UserDefaults.standard.set(budget5h, forKey: "budget5h"); recompute() }
    }
    @Published var budgetWeek: Double {
        didSet { UserDefaults.standard.set(budgetWeek, forKey: "budgetWeek"); recompute() }
    }
    @Published private(set) var scanning = false
    @Published private(set) var mountain = MountainLedger.load()
    /// Demo override for the mountain (fraction left) and the cutscene.
    var demoMountainLeft: Double?
    var demoCutscene = false
    /// Demo an account that has only a weekly limit (no 5-hour window).
    var demoWeeklyOnly = false
    /// When the cutscene began playing (demo recording); nil = loop it.
    var cutsceneStart: Date?

    var demo: PetState?
    var demoCycle = false
    let bridgeURL: URL
    let scanner: LogScanner
    private let queue = DispatchQueue(label: "tokenpet.scan", qos: .utility)
    private var bridge: (captured: Date, five: Meter?, week: Meter?)?
    private var codex: CodexReader.Reading?
    let codexRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
    private var timer: Timer?
    private var clock: () -> Date = Date.init

    init(bridgeURL: URL, logsRoot: URL, style: CharacterStyle?) {
        self.bridgeURL = bridgeURL
        self.scanner = LogScanner(root: logsRoot)
        let d = UserDefaults.standard
        self.style = style ?? CharacterStyle(rawValue: d.string(forKey: "style") ?? "") ?? .pixel
        self.budget5h = d.object(forKey: "budget5h") as? Double
        self.budgetWeek = d.object(forKey: "budgetWeek") as? Double ?? 60_000_000
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        if demo != nil || demoCycle { recompute(); return }
        guard !scanning else { return }
        scanning = true
        queue.async { [self] in
            scanner.scan()
            let b = Self.readBridge(bridgeURL)
            let c = CodexReader.read(root: codexRoot)
            DispatchQueue.main.async { [self] in
                bridge = b
                codex = c
                scanning = false
                mountain.absorb(scanner.events)
                recompute()
            }
        }
    }

    /// Blocking scan for CLI use (`--scan-report`).
    func scanNow() {
        scanner.scan()
        bridge = Self.readBridge(bridgeURL)
        codex = CodexReader.read(root: codexRoot)
        mountain.absorb(scanner.events)
        recompute()
    }

    /// Fraction of the current mountain still standing (demo-aware).
    var mountainLeft: Double { demoMountainLeft ?? mountain.left }
    var cutsceneDue: Bool { demoCutscene || (demo == nil && !demoCycle && mountain.cutscenePending) }
    func finishCutscene() {
        if demoCutscene { demoCutscene = false; objectWillChange.send(); return }
        mountain.nextMountain()
    }

    static func readBridge(_ url: URL) -> (captured: Date, five: Meter?, week: Meter?)? {
        guard let data = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = o["rate_limits"] as? [String: Any] else { return nil }
        func meter(_ k: String) -> Meter? {
            guard let w = rl[k] as? [String: Any], let p = (w["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
            let r = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return Meter(pct: p, resetsAt: r)
        }
        let cap = (o["captured_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? Date()
        return (cap, meter("five_hour"), meter("seven_day"))
    }

    func setDemo(_ s: PetState?) { demo = s; recompute() }

    /// Real night-time on this Mac: Grandpa yawns between digs.
    var night: Bool { let h = Calendar.current.component(.hour, from: clock()); return h >= 22 || h < 6 }

    func recompute() {
        let now = clock()
        snap = demo.map { Self.demoSnapshot($0, now: now, weeklyOnly: demoWeeklyOnly) } ?? live(now: now)
    }

    private func live(now: Date) -> Snapshot {
        var s = Snapshot()
        var resetsPassed: [Date] = []

        if let b = bridge {
            s.source = .official(captured: b.captured)
            func roll(_ m: Meter?) -> Meter? {
                guard var m = m else { return nil }
                if let r = m.resetsAt, r <= now { resetsPassed.append(r); m.pct = 0; m.resetsAt = nil }
                return m
            }
            s.five = roll(b.five); s.week = roll(b.week)
        } else {
            s.source = .measured
            // 5-hour: ccusage-style blocks that start at the hour of the first message.
            var blockStart: Date?, blockTokens = 0
            var blocks: [Date] = []
            for e in scanner.events {
                if let st = blockStart, e.time < st.addingTimeInterval(5 * 3600) { blockTokens += e.tokens; continue }
                if let st = blockStart { resetsPassed.append(st.addingTimeInterval(5 * 3600)) }
                blockStart = Calendar.current.dateInterval(of: .hour, for: e.time)?.start ?? e.time
                blocks.append(blockStart!)
                blockTokens = e.tokens
            }
            // Learn the real 5h ceiling: tokens spent in the block up to each "session limit" hit.
            let samples: [Int] = scanner.hits.filter { $0.kind == "5-hour" }.compactMap { hit in
                guard let st = blocks.last(where: { $0 <= hit.time }), hit.time < st.addingTimeInterval(5 * 3600) else { return nil }
                let t = scanner.events.filter { $0.time >= st && $0.time <= hit.time }.reduce(0) { $0 + $1.tokens }
                return t > 0 ? t : nil
            }.suffix(5).sorted()
            if !samples.isEmpty { s.learned5h = samples[samples.count / 2] }
            // The learned value is only reported (see --scan-report); on a multi-account Mac it is too
            // noisy to drive the pet, so the cap stays the user's budget.
            let cap5h = budget5h ?? 4_000_000
            if let st = blockStart {
                let end = st.addingTimeInterval(5 * 3600)
                if end > now {
                    s.five = Meter(pct: Double(blockTokens) / cap5h * 100, resetsAt: end, tokens: blockTokens)
                } else {
                    resetsPassed.append(end)
                    s.five = Meter(pct: 0, resetsAt: nil, tokens: 0)
                }
            }
            let weekTokens = scanner.events.reduce(0) { $0 + $1.tokens }
            s.week = Meter(pct: Double(weekTokens) / budgetWeek * 100, resetsAt: nil, tokens: weekTokens, rolling: true)
        }

        // Asleep: Claude Code itself said the limit was hit, and nothing succeeded afterwards.
        if let hit = scanner.hits.last, let wake = hit.wake {
            let usedAfter = scanner.events.last.map { $0.time > hit.time } ?? false
            if wake > now && !usedAfter { s.sleepUntil = wake; s.sleepReason = hit.kind }
            else if wake <= now { resetsPassed.append(wake) }
        }
        if s.sleepUntil == nil {
            let maxed = [s.five, s.week].compactMap { $0 }.filter { $0.pct >= 100 && !$0.rolling }
            if let m = maxed.max(by: { ($0.resetsAt ?? now) < ($1.resetsAt ?? now) }) {
                s.sleepUntil = m.resetsAt ?? now.addingTimeInterval(3600)
                s.sleepReason = "limit"
            }
        }
        // No 5-hour window (verified Ultra, or any plan where the status line omits it):
        // the carrier tracks today's share of the weekly limit instead. Never invent a 5-hour meter.
        if case .official = s.source, s.five == nil, let w = s.week, let r = w.resetsAt {
            let d = Daily.of(w, resetsAt: r, now: now, key: "daily.claude")
            s.daily = d
            if now.timeIntervalSince(d.dayStart) < 300 { resetsPassed.append(d.dayStart) }
            if s.sleepUntil == nil && d.fill >= 1 { s.sleepUntil = d.dayEnd; s.sleepReason = "daily" }
        }
        s.justReset = resetsPassed.filter { now.timeIntervalSince($0) < 300 }.max()
        s.codex = codex
        if let c = codex {
            if let f = c.five { s.codexFill = f.pct / 100 }
            else if let w = c.week, let r = w.resetsAt { s.codexFill = Daily.of(w, resetsAt: r, now: now, key: "daily.codex").fill }
            else { s.codexFill = (c.week?.pct ?? 0) / 100 }
        }
        s.projected = [Self.projection(s.five, window: 5 * 3600, now: now),
                       Self.projection(s.week, window: 7 * 86400, now: now)].compactMap { $0 }.max()
        s.state = Self.state(for: s, now: now)
        return s
    }

    /// Where this pace lands by the reset: used % divided by the share of the window gone by.
    static func projection(_ m: Meter?, window: TimeInterval, now: Date) -> Double? {
        guard let m, !m.rolling, let r = m.resetsAt, r > now else { return nil }
        let elapsed = 1 - r.timeIntervalSince(now) / window
        return m.pct / max(0.12, min(1, elapsed))
    }

    /// Carrier full = resting; just reset = morning; otherwise the working pace.
    static func state(for s: Snapshot, now: Date) -> PetState {
        if let w = s.sleepUntil, w > now { return .resting }
        if s.justReset != nil { return .morning }
        let top = [s.five, s.week].compactMap { $0 }.filter { !$0.rolling }.map(\.pct).max() ?? 0
        let pace = s.projected ?? top
        if top >= 80 || pace >= 110 { return .straining }
        if pace >= 75 { return .steady }
        return .lively
    }

    static func demoSnapshot(_ st: PetState, now: Date, weeklyOnly: Bool = false) -> Snapshot {
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int = 0, daysAhead: Int = 0) -> Date {
            var d = cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
            if d <= now { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
            return cal.date(byAdding: .day, value: daysAhead, to: d) ?? d
        }
        var s = Snapshot(source: .demo, state: st)
        let codexPct: [PetState: Double] = [.lively: 18, .steady: 42, .straining: 66, .resting: 100, .morning: 4]
        s.codex = CodexReader.Reading(five: nil, week: Meter(pct: codexPct[st] ?? 18, resetsAt: at(10, daysAhead: 1)), at: now)
        let weekly = at(9, daysAhead: 3)
        switch st {
        case .lively:    s.five = Meter(pct: 22, resetsAt: now.addingTimeInterval(2 * 3600 + 13 * 60)); s.week = Meter(pct: 21, resetsAt: weekly)
        case .steady:    s.five = Meter(pct: 48, resetsAt: now.addingTimeInterval(2 * 3600)); s.week = Meter(pct: 40, resetsAt: weekly)
        case .straining: s.five = Meter(pct: 91, resetsAt: now.addingTimeInterval(48 * 60)); s.week = Meter(pct: 63, resetsAt: weekly)
        case .resting:   let w = at(9); s.five = Meter(pct: 100, resetsAt: w); s.week = Meter(pct: 72, resetsAt: weekly)
                         s.sleepUntil = w; s.sleepReason = "5-hour"
        case .morning:   s.five = Meter(pct: 0, resetsAt: nil); s.week = Meter(pct: 72, resetsAt: weekly); s.justReset = now
        }
        s.projected = projection(s.five, window: 5 * 3600, now: now)
        s.codexFill = (s.codex?.week?.pct ?? 0) / 100
        if weeklyOnly {
            // an account without a 5-hour window: the carrier is today's share of the week
            let fills: [PetState: Double] = [.lively: 0.3, .steady: 0.62, .straining: 0.9, .resting: 1.0, .morning: 0]
            let dayStart = cal.date(bySettingHour: 4, minute: 0, second: 0, of: now).map { $0 > now ? $0.addingTimeInterval(-86400) : $0 } ?? now
            let f = fills[st] ?? 0.3
            s.daily = Daily(fill: f, usedToday: f * 100 / 7, share: 100 / 7, dayStart: dayStart, dayEnd: dayStart.addingTimeInterval(86400), estimated: false)
            s.five = nil
            s.week = Meter(pct: [.lively: 31, .steady: 44, .straining: 58, .resting: 61, .morning: 61][st] ?? 31, resetsAt: weekly)
            s.projected = projection(s.week, window: 7 * 86400, now: now)
            if st == .resting { s.sleepUntil = s.daily?.dayEnd; s.sleepReason = "daily" }
        }
        return s
    }

    /// Menu-bar redraw rate: smooth enough for the physics, slow when there is little motion.
    var menuBarFPS: Double {
        if Motion.reduce { return 1 }
        switch snap.state { case .resting: return 4; default: return 8 }
    }

    /// `--allow-capture` (demo recording only): windows stay capturable without changing the saved setting.
    var captureAllowedForDemo = false

    /// Keep the pet and the numbers out of screen shares and recordings (default on).
    @Published var hideFromCapture: Bool = UserDefaults.standard.object(forKey: "hideFromCapture") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hideFromCapture, forKey: "hideFromCapture") }
    }
}
