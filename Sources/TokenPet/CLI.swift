import Foundation

/// The command line for people and agents (README "Command line"). Stable `--json` output, plain-language
/// errors on stderr, exit 1 on an error:
///   TokenPet status [--json]                 is Claude Code connected, and the last limits it reported
///   TokenPet setup [--dry-run] [--json]      connect Claude Code's status line (ClaudeConnect)
///   TokenPet setup --undo [--dry-run] [--json]
enum CLI {
    struct Result: Equatable { var code: Int32 = 0; var out = ""; var err = "" }

    /// nil when `args` (without the program name) is not a CLI command: the app starts as usual.
    static func run(_ args: [String], home: URL, bridge: URL, now: Date = Date()) -> Result? {
        guard let cmd = args.first, ["status", "setup"].contains(cmd) else { return nil }
        let asJSON = args.contains("--json"), dir = bridge.deletingLastPathComponent()
        if cmd == "status" { return status(home: home, bridge: bridge, dir: dir, json: asJSON, now: now) }
        let undo = args.contains("--undo"), dry = args.contains("--dry-run")
        do {
            let change = undo ? try ClaudeConnect.disconnect(home: home, dir: dir) : try ClaudeConnect.connect(home: home, dir: dir)
            // the bridge goes in only after connect found ~/.claude (installing first would make it); again when already connected
            if !undo && !dry && !StatusLineSetup.install(into: dir) { throw ClaudeConnect.Problem.noBridge }
            guard let change else {
                let r = undo ? "not_connected" : "already_connected"
                return Result(out: asJSON ? encode(["result": r, "settings": ClaudeConnect.settingsURL(home: home).path])
                                          : (undo ? "Claude Code's status line does not use Token Yugong; nothing to undo.\n"
                                                  : "Already connected; nothing changed.\n"))
            }
            let backup = dry ? nil : try ClaudeConnect.apply(change, backupDir: dir, now: now)
            let r = dry ? "dry_run" : undo ? "disconnected" : "connected"
            if asJSON {
                return Result(out: encode(["result": r, "settings": change.settings.path, "before": n(change.before), "after": n(change.after), "backup": n(backup?.path)]))
            }
            var s = dry ? "Would change \(change.settings.path) (nothing written):\n" : "Changed \(change.settings.path)\n"
            s += "statusLine before:\n\(change.before ?? "(none)")\nstatusLine after:\n\(change.after ?? "(none)")\n"
            s += "Every other setting is unchanged.\n"
            if let backup { s += "Backup: \(backup.path)\n" + (undo ? "" : "Undo: TokenPet setup --undo\n") }
            if !dry && !undo { s += "The numbers arrive after Claude Code's next reply.\n" }
            return Result(out: s)
        } catch let p as ClaudeConnect.Problem {
            return failure(p.code, p.message, json: asJSON)
        } catch {
            return failure("write_failed", "\(error.localizedDescription)", json: asJSON)
        }
    }

    private static func status(home: URL, bridge: URL, dir: URL, json: Bool, now: Date) -> Result {
        let claudeHere = FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude").path)
        let conn = claudeHere ? ClaudeConnect.state(home: home, dir: dir).rawValue : "no_claude"
        let r = UsageModel.readBridge(bridge)
        func meter(_ m: Meter?) -> [String: Any]? {
            m.map { ["used_percentage": $0.pct, "resets_at": n($0.resetsAt.map { Int($0.timeIntervalSince1970) })] }
        }
        if json {
            let reading: [String: Any]? = r.map {
                ["captured_at": Int($0.at.timeIntervalSince1970), "age_seconds": Int(now.timeIntervalSince($0.at)),
                 "five_hour": n(meter($0.five)), "seven_day": n(meter($0.week))]
            }
            return Result(out: encode(["claude": ["connection": conn, "settings": ClaudeConnect.settingsURL(home: home).path,
                                                  "limits_file": bridge.path, "reading": n(reading)]]))
        }
        var s = "Claude Code: " + [
            "connected": "connected", "chained": "connected (your own status line runs after the bridge)",
            "manual": "connected by hand", "not_connected": "not connected - run: TokenPet setup",
            "no_claude": "not set up on this Mac (no ~/.claude)",
        ][conn, default: conn] + "\n"
        if let r {
            s += "last reading: \(Fmt.clock(r.at)) (\(Int(now.timeIntervalSince(r.at)) / 60) min ago)\n"
            if let f = r.five { s += "5h: \(Fmt.pct(f.pct))" + (f.resetsAt.map { " resets \(Fmt.clock($0))" } ?? "") + "\n" }
            if let w = r.week { s += "week: \(Fmt.pct(w.pct))" + (w.resetsAt.map { " resets \(Fmt.clock($0))" } ?? "") + "\n" }
        } else {
            s += "no reading yet (it comes after Claude Code's next reply)\n"
        }
        return Result(out: s)
    }

    private static func failure(_ code: String, _ message: String, json: Bool) -> Result {
        Result(code: 1, out: json ? encode(["error": code, "message": message]) : "", err: message + "\n")
    }

    /// JSON null for a missing value (an Optional inside Any would not serialize).
    private static func n(_ v: Any?) -> Any { v ?? NSNull() }

    private static func encode(_ o: [String: Any]) -> String {
        let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes])
        return (d.map { String(decoding: $0, as: UTF8.self) } ?? "{}") + "\n"
    }
}

extension ClaudeConnect.Problem {
    /// The stable name in `--json` errors.
    var code: String {
        switch self {
        case .noClaude: return "no_claude"
        case .unreadable: return "unreadable_settings"
        case .unknownForm: return "unknown_status_line"
        case .noBridge: return "no_bridge"
        }
    }
}
