import Foundation

/// Claude's limits come from the unmodified Claude Code: `claude -p /usage`, once per profile (LOGIC.md
/// "Accounts"). A profile is the default ~/.claude or a CLAUDE_CONFIG_DIR folder the user added. It holds one
/// login, so its answer belongs to exactly that login and is the server's, at the moment it was asked. Yugong
/// never reads a token and never calls an Anthropic endpoint itself.
enum ClaudeUsage {
    /// No session file, no user or plugin settings (so no hooks run), no MCP servers.
    static let arguments = ["-p", "/usage", "--no-session-persistence", "--setting-sources", "project",
                            "--strict-mcp-config", "--output-format", "stream-json", "--verbose"]

    enum Answer: Equatable {
        /// The server's rows, asked just now.
        case limits(Reading)
        /// Claude Code answered without fresh rows: rate limited, held back, signed out, an API key, no plan limits.
        case noLimits
        /// Not output this parser knows (another Claude Code version?), or the run failed.
        case unreadable
    }

    /// The stream-json lines of `claude -p /usage`. Only `usage_report.rate_limits.limits[]` counts, each row
    /// classified by its `kind` as Claude Code's own schema says ("session" = 5-hour, "weekly_all" = weekly);
    /// the human-readable text is never parsed. Checked against Claude Code 2.1.332 (Tests: ClaudeUsageTests).
    static func parse(_ output: Data, at now: Date) -> Answer {
        var report: [String: Any]?
        for line in output.split(separator: UInt8(ascii: "\n")) {
            if let o = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
               let r = o["usage_report"] as? [String: Any] { report = r }
        }
        guard let report, let rateLimits = report["rate_limits"] else { return .unreadable }
        if rateLimits is NSNull { return .noLimits }
        guard let rl = rateLimits as? [String: Any], let rows = rl["limits"] else { return .unreadable }
        // Claude Code drops the rows when it answers from its own cached snapshot instead of the server.
        if rows is NSNull { return .noLimits }
        guard let list = rows as? [[String: Any]] else { return .unreadable }
        var reading = Reading(five: nil, week: nil, at: now)
        for row in list {
            guard let kind = row["kind"] as? String, kind == "session" || kind == "weekly_all" else { continue }
            guard let meter = meter(row) else { return .unreadable }
            if kind == "session" { reading.five = reading.five ?? meter } else { reading.week = reading.week ?? meter }
        }
        return reading.five == nil && reading.week == nil ? .noLimits : .limits(reading)
    }

    /// percent 0-100 and an ISO 8601 `resets_at` (or null); anything else is not a row this parser knows.
    private static func meter(_ row: [String: Any]) -> Meter? {
        guard let p = (row["percent"] as? NSNumber)?.doubleValue, p.isFinite, p >= 0 else { return nil }
        let reset: Date?
        switch row["resets_at"] {
        case nil, is NSNull: reset = nil
        case let s as String:
            guard let d = Limits.iso.date(from: s) ?? plainISO.date(from: s) else { return nil }
            reset = d
        default: return nil
        }
        return Meter(pct: min(p, 100), resetsAt: reset)
    }

    private static let plainISO: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    /// The profile's signed-in email from its `.claude.json` (`oauthAccount.emailAddress`): the row's name.
    static func login(config data: Data?) -> String? {
        guard let data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let a = o["oauthAccount"] as? [String: Any], let e = a["emailAddress"] as? String, !e.isEmpty else { return nil }
        return e
    }

    /// `.claude.json` of a profile: ~/.claude.json for the default, `<dir>/.claude.json` for CLAUDE_CONFIG_DIR.
    static func configURL(dir: String?, home: URL) -> URL {
        dir.map { URL(fileURLWithPath: $0).appendingPathComponent(".claude.json") } ?? home.appendingPathComponent(".claude.json")
    }

    /// Where Claude Code's installers put `claude`; a Mac app does not get the login shell's PATH.
    static func executable(home: URL, fm: FileManager = .default) -> URL? {
        [home.appendingPathComponent(".local/bin/claude"), home.appendingPathComponent(".claude/local/claude"),
         URL(fileURLWithPath: "/opt/homebrew/bin/claude"), URL(fileURLWithPath: "/usr/local/bin/claude")]
            .first { fm.isExecutableFile(atPath: $0.path) }
    }

    /// Runs `claude -p /usage` for one profile and waits (call it off the main thread). `cwd` is an empty folder
    /// of Yugong's own, so no project settings apply and Claude Code keeps one project entry for it.
    static func ask(dir: String?, home: URL, cwd: URL, timeout: TimeInterval = 30) -> Answer {
        guard let exe = executable(home: home) else { return .unreadable }
        try? FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = exe
        p.arguments = arguments
        p.currentDirectoryURL = cwd
        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_CONFIG_DIR"] = dir
        env["PATH"] = [exe.deletingLastPathComponent().path, "/usr/bin", "/bin", "/opt/homebrew/bin", "/usr/local/bin",
                       env["PATH"]].compactMap { $0 }.joined(separator: ":")
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return .unreadable }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parse(data, at: Date())
    }
}

/// When Yugong asks one profile (README "How often Yugong asks Claude Code"). Asking is rare on purpose: the
/// account belongs to the user, and a tool that keeps poking an endpoint can look like abuse.
struct ClaudeAsk: Equatable, Codable {
    var lastAsked: Date?
    /// 0 = not backing off; else the current hold, doubled after each failed ask.
    var backoff: TimeInterval = 0
    var heldUntil: Date?
    /// After a failed ask the slow background refresh leaves this profile alone until the popover is opened.
    var stopped = false

    static let minimumGap: TimeInterval = 5 * 60
    static let firstBackoff: TimeInterval = 3600
    static let longestBackoff: TimeInterval = 24 * 3600
    static let backgroundInterval: TimeInterval = 30 * 60
    static let backgroundJitter: TimeInterval = 5 * 60

    enum Reason { case start, popover, background }

    /// At most once per 5 minutes whatever the reason, never while held back; the background refresh also
    /// needs its setting on and the profile not stopped. A clock set backwards does not lock a profile out.
    func allows(_ reason: Reason, backgroundOn: Bool, now: Date) -> Bool {
        if let h = heldUntil, now < h, h.timeIntervalSince(now) <= Self.longestBackoff { return false }
        if let l = lastAsked, (0..<Self.minimumGap).contains(now.timeIntervalSince(l)) { return false }
        return reason != .background || (backgroundOn && !stopped)
    }

    /// Only a fresh answer clears the backoff; anything else holds the profile for 1 h, 2 h, 4 h … up to a day.
    mutating func record(_ answer: ClaudeUsage.Answer, now: Date) {
        lastAsked = now
        if case .limits = answer { backoff = 0; heldUntil = nil; stopped = false; return }
        backoff = backoff == 0 ? Self.firstBackoff : min(backoff * 2, Self.longestBackoff)
        heldUntil = now.addingTimeInterval(backoff)
        stopped = true
    }

    /// `random` in 0...1: 30 minutes ± 5.
    static func nextBackground(random: Double) -> TimeInterval {
        backgroundInterval + (min(max(random, 0), 1) * 2 - 1) * backgroundJitter
    }
}
