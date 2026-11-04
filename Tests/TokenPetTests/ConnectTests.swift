import Foundation
import Testing
@testable import TokenPet

// One-click / one-command connect (ClaudeConnect, CLI): only settings.json's statusLine changes, an existing
// status line is kept by chaining, undo puts the file back byte for byte. Every test uses a throwaway home.

@Suite struct Connect {
    let fm = FileManager.default

    /// A throwaway home; `claude` makes ~/.claude, `settings` writes ~/.claude/settings.json.
    func home(claude: Bool = true, settings: String? = nil) throws -> URL {
        let h = fm.temporaryDirectory.appendingPathComponent("tokenpet-connect-\(UUID().uuidString)")
        try fm.createDirectory(at: claude ? h.appendingPathComponent(".claude") : h, withIntermediateDirectories: true)
        if let settings { try Data(settings.utf8).write(to: ClaudeConnect.settingsURL(home: h)) }
        return h
    }
    func dir(_ h: URL) -> URL { h.appendingPathComponent(".claude/token-pet") }
    func text(_ h: URL) throws -> String { try String(contentsOf: ClaudeConnect.settingsURL(home: h), encoding: .utf8) }
    func json(_ h: URL) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: ClaudeConnect.settingsURL(home: h))) as? [String: Any])
    }
    func command(_ h: URL) throws -> String? { ((try json(h))["statusLine"] as? [String: Any])?["command"] as? String }
    @discardableResult func connect(_ h: URL) throws -> Bool {
        guard let c = try ClaudeConnect.connect(home: h, dir: dir(h)) else { return false }
        try ClaudeConnect.apply(c, backupDir: dir(h))
        return true
    }
    @discardableResult func undo(_ h: URL) throws -> Bool {
        guard let c = try ClaudeConnect.disconnect(home: h, dir: dir(h)) else { return false }
        try ClaudeConnect.apply(c, backupDir: dir(h))
        return true
    }
    let base = "sh ~/.claude/token-pet/statusline-bridge.sh"

    @Test func noClaudeCodeIsAClearErrorAndMakesNothing() throws {
        let h = try home(claude: false)
        defer { try? fm.removeItem(at: h) }
        #expect(throws: ClaudeConnect.Problem.noClaude("~/.claude")) { try ClaudeConnect.connect(home: h, dir: dir(h)) }
        let r = try #require(CLI.run(["setup", "--json"], home: h, bridge: dir(h).appendingPathComponent("limits.json")))
        #expect(r.code == 1 && r.out.contains(#""error":"no_claude""#) && r.err.contains("Claude Code"))
        #expect(!fm.fileExists(atPath: h.appendingPathComponent(".claude").path))   // not even the bridge folder
    }

    @Test func noSettingsFileGetsOneWithTheStatusLine() throws {
        let h = try home()
        defer { try? fm.removeItem(at: h) }
        #expect(try connect(h))
        #expect(try text(h) == "{\n  \"statusLine\": {\n    \"type\": \"command\",\n    \"command\": \"\(base)\"\n  }\n}\n")
        #expect(ClaudeConnect.state(home: h, dir: dir(h)) == .connected)
        #expect(try undo(h))
        #expect(try json(h).isEmpty)
    }

    @Test func otherSettingsStayByteForByteAndUndoRestoresTheFile() throws {
        // the member order, the odd spacing, the unicode, nested objects: none of it may move
        let original = "{\n    \"model\": \"opus\",\n    \"env\": {\"A\": \"1\", \"B\": [1, 2.50, null]},\n    \"note\":  \"한글 \\\"q\\\" }{\"\n}\n"
        let h = try home(settings: original)
        defer { try? fm.removeItem(at: h) }
        #expect(try connect(h))
        let after = try text(h)
        #expect(after.hasPrefix("{\n    \"statusLine\": {\n        \"type\": \"command\",\n        \"command\": \"\(base)\"\n    },"))  // the file's own indent
        #expect(after.replacingOccurrences(of: "\n    \"statusLine\": {\n        \"type\": \"command\",\n        \"command\": \"\(base)\"\n    },", with: "") == original)
        #expect(try connect(h) == false)            // idempotent: nothing to do, nothing written
        #expect(try text(h) == after)
        #expect(try undo(h))
        #expect(try text(h) == original)
        #expect(try undo(h) == false)
        // two backups (connect, undo) even within one second, the first is the file as it was
        let backups = try fm.contentsOfDirectory(atPath: dir(h).path).filter { $0.hasSuffix(".bak") }.sorted()
        #expect(backups.count == 2)
        #expect(try String(contentsOf: dir(h).appendingPathComponent(backups.first { !$0.contains("-2.bak") }!), encoding: .utf8) == original)
    }

    @Test func anExistingStatusLineIsChainedAndComesBack() throws {
        let mine = #"bash ~/bin/my line.sh "$(whoami)" 'x'"#
        let e = JSONEncoder()
        e.outputFormatting = .withoutEscapingSlashes   // as Claude Code writes it; a "\/" would come back as "/" (same value)
        let original = "{\n  \"statusLine\": {\n    \"type\": \"command\",\n    \"command\": \(String(decoding: try e.encode(mine), as: UTF8.self)),\n    \"padding\": 0\n  },\n  \"model\": \"opus\"\n}\n"
        let h = try home(settings: original)
        defer { try? fm.removeItem(at: h) }
        #expect(try connect(h))
        let cmd = try #require(try command(h))
        #expect(cmd == base + " --chain " + ClaudeConnect.shq(mine))
        #expect(ClaudeConnect.unwrap(cmd, base: base) == mine)
        #expect(((try json(h))["statusLine"] as? [String: Any])?["padding"] as? Int == 0)   // its other fields stay
        #expect(ClaudeConnect.state(home: h, dir: dir(h)) == .chained)
        #expect(try connect(h) == false)            // never wrapped twice
        #expect(try undo(h))
        #expect(try text(h) == original)
    }

    @Test func connectThenUndoIsByteIdenticalForAnyShape() throws {
        for original in ["{}", "{}\n", "{\"model\":\"opus\",\"x\":[1]}", "{\n\t\"model\": \"opus\"\n}", "  {  \"a\" : 1 }  "] {
            let h = try home(settings: original)
            defer { try? fm.removeItem(at: h) }
            #expect(try connect(h))
            #expect(try command(h) == base)
            #expect(try undo(h))
            #expect(try text(h) == original)
        }
    }

    @Test func undoRemovesTheMemberWhereverItIs() throws {
        let sl = "\"statusLine\": {\"type\": \"command\", \"command\": \"\(base)\"}"
        for (withIt, without) in [
            ("{\n  \(sl),\n  \"a\": 1\n}", "{\n  \"a\": 1\n}"),                         // first
            ("{\n  \"a\": 1,\n  \(sl),\n  \"b\": 2\n}", "{\n  \"a\": 1,\n  \"b\": 2\n}"), // middle
            ("{\n  \"a\": 1,\n  \(sl)\n}", "{\n  \"a\": 1\n}"),                          // last
            ("{\(sl)}", "{}"),                                                            // only
        ] {
            let h = try home(settings: withIt)
            defer { try? fm.removeItem(at: h) }
            #expect(try undo(h))
            #expect(try text(h) == without)
        }
    }

    @Test func whatItCannotReadIsLeftAlone() throws {
        for (settings, problem) in [
            ("{ \"model\": \"opus\", // a comment\n}", ClaudeConnect.Problem.unreadable("settings.json")),
            ("[1, 2]", .unreadable("settings.json")),
            ("{ \"model\": \"opus\", }", .unreadable("settings.json")),   // Foundation takes it, Claude Code would not
            ("{\"statusLine\": {\"type\": \"command\"}}", .unknownForm),
        ] {
            let h = try home(settings: settings)
            defer { try? fm.removeItem(at: h) }
            #expect(throws: problem) { try ClaudeConnect.connect(home: h, dir: dir(h)) }
            #expect(try text(h) == settings)
        }
    }

    /// The old instructions had people call the bridge from their own script: that is theirs, not ours to wrap or undo.
    @Test func aHandMadeChainIsNotTouched() throws {
        let settings = "{\"statusLine\": {\"type\": \"command\", \"command\": \"input=$(cat); printf '%s' \\\"$input\\\" | sh ~/.claude/token-pet/statusline-bridge.sh >/dev/null; echo hi\"}}"
        let h = try home(settings: settings)
        defer { try? fm.removeItem(at: h) }
        #expect(ClaudeConnect.state(home: h, dir: dir(h)) == .manual)
        #expect(try connect(h) == false)
        #expect(throws: ClaudeConnect.Problem.unknownForm) { try ClaudeConnect.disconnect(home: h, dir: dir(h)) }
        #expect(try text(h) == settings)
    }

    /// A dotfiles repo links settings.json: the link stays a link, the file keeps its permissions.
    @Test func aSymlinkAndPermissionsSurvive() throws {
        let h = try home()
        defer { try? fm.removeItem(at: h) }
        let real = h.appendingPathComponent("dotfiles-settings.json")
        try Data("{\"model\": \"opus\"}\n".utf8).write(to: real)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: real.path)
        try fm.createSymbolicLink(at: ClaudeConnect.settingsURL(home: h), withDestinationURL: real)
        #expect(try connect(h))
        #expect(try fm.destinationOfSymbolicLink(atPath: ClaudeConnect.settingsURL(home: h).path) == real.path)
        #expect(try String(contentsOf: real, encoding: .utf8).contains("statusline-bridge.sh"))
        #expect((try fm.attributesOfItem(atPath: real.path))[.posixPermissions] as? Int == 0o600)
    }

    @Test func shellQuotingRoundTrips() {
        for s in ["", "a", "it's", "'''", #"a "b" $c `d` \e"#, "line\nbreak"] {
            #expect(ClaudeConnect.unwrap(base + " --chain " + ClaudeConnect.shq(s), base: base) == s)
        }
        #expect(ClaudeConnect.unwrap(base + " --chain 'a'b'", base: base) == nil)   // not something we wrote
        #expect(ClaudeConnect.unwrap(base, base: base) == nil)
    }

    /// The bridge with `--chain`: saves the limits, then the user's own line gets the same JSON and is what shows.
    @Test func theBridgeRunsTheChainedLine() throws {
        let h = try home()
        defer { try? fm.removeItem(at: h) }
        let script = try #require(StatusLineSetup.bundledBridge)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path, "--chain", #"printf 'mine:'; cat; exit 3"#]
        p.environment = ["HOME": h.path, "TOKENPET_DIR": dir(h).path, "PATH": "/usr/bin:/bin"]
        let i = Pipe(), o = Pipe()
        p.standardInput = i; p.standardOutput = o
        try p.run()
        let input = #"{"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1793620000}}}"#
        i.fileHandleForWriting.write(Data(input.utf8)); try i.fileHandleForWriting.close()
        p.waitUntilExit()
        #expect(String(decoding: o.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == "mine:" + input)
        #expect(p.terminationStatus == 3)
        let saved = try Data(contentsOf: dir(h).appendingPathComponent("limits.json"))
        #expect(Limits.bridge(saved, fileDate: Date())?.five?.pct == 42)
    }

    @Test func theCommandLine() throws {
        let h = try home(settings: "{\"model\": \"opus\"}\n")
        defer { try? fm.removeItem(at: h) }
        let limits = dir(h).appendingPathComponent("limits.json")
        func run(_ a: String...) throws -> CLI.Result { try #require(CLI.run(a, home: h, bridge: limits)) }
        #expect(CLI.run(["--scan-report"], home: h, bridge: limits) == nil)   // not ours: the app starts

        #expect(try run("status", "--json").out.contains(#""connection":"not_connected""#))
        let dry = try run("setup", "--dry-run", "--json")
        #expect(dry.code == 0 && dry.out.contains(#""result":"dry_run""#) && dry.out.contains(#""backup":null"#))
        #expect(try text(h) == "{\"model\": \"opus\"}\n")                       // a dry run writes nothing
        #expect(try run("setup", "--json").out.contains(#""result":"connected""#))
        #expect(fm.fileExists(atPath: dir(h).appendingPathComponent("statusline-bridge.sh").path))
        #expect(try run("setup", "--json").out.contains(#""result":"already_connected""#))

        try Data(#"{"captured_at":1793600000,"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1793620000}}}"#.utf8).write(to: limits)
        let st = try run("status", "--json")
        let o = try #require(try JSONSerialization.jsonObject(with: Data(st.out.utf8)) as? [String: Any])
        let c = try #require(o["claude"] as? [String: Any]), r = try #require(c["reading"] as? [String: Any])
        #expect(c["connection"] as? String == "connected")
        #expect(r["captured_at"] as? Int == 1_793_600_000)
        #expect((r["five_hour"] as? [String: Any])?["used_percentage"] as? Double == 42)
        #expect(r["seven_day"] is NSNull)

        #expect(try run("setup", "--undo", "--json").out.contains(#""result":"disconnected""#))
        #expect(try text(h) == "{\"model\": \"opus\"}\n")
        #expect(try run("setup", "--undo", "--json").out.contains(#""result":"not_connected""#))
    }
}
