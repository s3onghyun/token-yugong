import Foundation

/// One-click / one-command connect: puts the bridge into the `statusLine` of ~/.claude/settings.json.
/// A status line the user already has is kept: the bridge runs it (`--chain`) and shows its output.
/// Only that one key changes, byte for byte the rest of the file stays; the old file is backed up next to
/// limits.json, and `disconnect` puts the old command back (it is inside the wrapped command itself).
enum ClaudeConnect {
    enum Problem: Error, Equatable {
        case noClaude(String)        // ~/.claude is missing: Claude Code was never run here
        case unreadable(String)      // settings.json is not a JSON object we can read; left alone
        case unknownForm             // a statusLine without a command string, or a hand-made bridge chain
        case noBridge                // no bridge script to install (a broken build)

        var message: String {
            switch self {
            case .noClaude(let p):
                return L.t("Claude Code is not set up on this Mac (\(p) is missing). Install Claude Code, run it once, then try again.",
                           "이 Mac에 Claude Code가 설정되어 있지 않아요(\(p) 없음). Claude Code를 설치해 한 번 실행한 뒤 다시 해 보세요.",
                           "この Mac に Claude Code の設定がありません（\(p) がありません）。Claude Code をインストールして一度起動してから、もう一度お試しください。",
                           "这台 Mac 上还没有设置 Claude Code（缺少 \(p)）。请安装 Claude Code 并运行一次，然后再试。")
            case .unreadable(let p):
                return L.t("\(p) is not a JSON object I can read, so I left it alone. Fix it or add the snippet by hand.",
                           "\(p)이(가) 읽을 수 있는 JSON 객체가 아니라 건드리지 않았어요. 고치거나 스니펫을 직접 넣어 주세요.",
                           "\(p) は読める JSON オブジェクトではないので、触りませんでした。修正するか、スニペットを手で追加してください。",
                           "\(p) 不是可读取的 JSON 对象，所以没有改动它。请修好它，或手动加入代码片段。")
            case .unknownForm:
                return L.t("Your statusLine is set up in a way I don't recognise, so I left it alone. Change it by hand.",
                           "statusLine이 알아볼 수 없는 형태라 건드리지 않았어요. 직접 고쳐 주세요.",
                           "statusLine が見慣れない形なので、触りませんでした。手で変更してください。",
                           "statusLine 的写法我认不出来，所以没有改动。请手动修改。")
            case .noBridge:
                return L.t("The bridge script is missing from the app. Reinstall Token Yugong.",
                           "앱에 브리지 스크립트가 없어요. Token Yugong을 다시 설치해 주세요.",
                           "アプリにブリッジスクリプトがありません。Token Yugong を入れ直してください。",
                           "应用里缺少桥接脚本。请重新安装 Token Yugong。")
            }
        }
    }

    /// A write that has not happened yet: the whole new file, and the statusLine before and after (for the preview).
    struct Change: Equatable {
        let settings: URL
        let old: Data?
        let new: Data
        let before: String?   // the statusLine value text, nil = none
        let after: String?
    }

    enum State: String { case notConnected = "not_connected", connected, chained, manual }

    static func settingsURL(home: URL) -> URL { home.appendingPathComponent(".claude/settings.json") }

    /// Is the bridge in settings.json's statusLine, and how. `manual` = it mentions the bridge in a form this app did not write.
    static func state(home: URL, dir: URL) -> State {
        guard let b = try? Data(contentsOf: settingsURL(home: home)), let cmd = try? command(in: [UInt8](b)) else { return .notConnected }
        let base = StatusLineSetup.command(dir: dir, home: home)
        if cmd == base { return .connected }
        if unwrap(cmd, base: base) != nil { return .chained }
        return cmd.contains("statusline-bridge.sh") ? .manual : .notConnected
    }

    /// The change that connects the bridge, or nil if it is already there.
    static func connect(home: URL, dir: URL) throws -> Change? {
        let (url, old) = try read(home: home)
        let bytes = old.map { [UInt8]($0) } ?? Array("{}\n".utf8)
        let base = StatusLineSetup.command(dir: dir, home: home)
        let obj = try object(bytes, url)
        if let m = obj.members.first(where: { $0.key == "statusLine" }) {
            guard let current = try command(in: bytes) else { throw Problem.unknownForm }
            if current.contains("statusline-bridge.sh") { return nil }   // ours, or the user's own chain: never wrap twice
            let inner = try object(Array(bytes[m.value]), url)
            guard let c = inner.members.first(where: { $0.key == "command" }) else { throw Problem.unknownForm }
            let at = (m.value.lowerBound + c.value.lowerBound)..<(m.value.lowerBound + c.value.upperBound)
            return try change(url, old, splice(bytes, at, json(base + " --chain " + shq(current))))
        }
        guard let first = obj.members.first else {
            let v = "{\n    \"type\": \"command\",\n    \"command\": \(json(base))\n  }"
            return try change(url, old, splice(bytes, (obj.open + 1)..<obj.close, "\n  \"statusLine\": \(v)\n"))
        }
        // before the first member, followed by the same whitespace that came before it: undo cuts exactly this back out
        let indent = indentation(bytes, first.start), ws = String(decoding: bytes[(obj.open + 1)..<first.start], as: UTF8.self)
        let value = indent.isEmpty ? "{\"type\": \"command\", \"command\": \(json(base))}"
            : "{\n\(indent)\(indent)\"type\": \"command\",\n\(indent)\(indent)\"command\": \(json(base))\n\(indent)}"
        return try change(url, old, splice(bytes, first.start..<first.start, "\"statusLine\": \(value),\(ws)"))
    }

    /// The change that takes the bridge out again (the chained command comes back), or nil if it is not there.
    static func disconnect(home: URL, dir: URL) throws -> Change? {
        let (url, old) = try read(home: home)
        guard let old else { return nil }
        let bytes = [UInt8](old), obj = try object(bytes, url)
        guard let m = obj.members.first(where: { $0.key == "statusLine" }), let cmd = try command(in: bytes) else { return nil }
        let base = StatusLineSetup.command(dir: dir, home: home)
        if let original = unwrap(cmd, base: base) {
            let inner = try object(Array(bytes[m.value]), url)
            guard let c = inner.members.first(where: { $0.key == "command" }) else { throw Problem.unknownForm }
            let at = (m.value.lowerBound + c.value.lowerBound)..<(m.value.lowerBound + c.value.upperBound)
            return try change(url, old, splice(bytes, at, json(original)))
        }
        if cmd == base { return try change(url, old, splice(bytes, removal(bytes, obj, m), "")) }
        if cmd.contains("statusline-bridge.sh") { throw Problem.unknownForm }   // the user's own chain: theirs to undo
        return nil
    }

    /// Writes `c`: the old file goes to `backupDir` first; the file keeps its permissions, and a symlinked
    /// settings.json (a dotfiles repo) is written through, not replaced. Returns the backup, if any.
    @discardableResult static func apply(_ c: Change, backupDir: URL, now: Date = Date()) throws -> URL? {
        let fm = FileManager.default, target = c.settings.resolvingSymlinksInPath()
        var backup: URL?
        if let old = c.old {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            f.locale = Locale(identifier: "en_US_POSIX")
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
            // never over an older backup (a connect and an undo in the same second would lose the original)
            var name = "settings.json.\(f.string(from: now)).bak", n = 1
            while fm.fileExists(atPath: backupDir.appendingPathComponent(name).path) { n += 1; name = "settings.json.\(f.string(from: now))-\(n).bak" }
            backup = backupDir.appendingPathComponent(name)
            try old.write(to: backup!, options: .withoutOverwriting)
        }
        let perms = (try? fm.attributesOfItem(atPath: target.path))?[.posixPermissions]
        try c.new.write(to: target, options: .atomic)
        if let perms { try fm.setAttributes([.posixPermissions: perms], ofItemAtPath: target.path) }
        return backup
    }

    // MARK: - the command string

    /// `'it'\''s'`: one shell word.
    static func shq(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// The user's command inside `<base> --chain '<cmd>'`, or nil if `cmd` is not that form.
    static func unwrap(_ cmd: String, base: String) -> String? {
        let prefix = base + " --chain "
        guard cmd.hasPrefix(prefix) else { return nil }
        let q = String(cmd.dropFirst(prefix.count))
        guard q.count >= 2, q.hasPrefix("'"), q.hasSuffix("'") else { return nil }
        let inner = String(q.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
        return shq(inner) == q ? inner : nil
    }

    private static func json(_ s: String) -> String {
        let e = JSONEncoder()
        e.outputFormatting = .withoutEscapingSlashes
        return String(decoding: try! e.encode(s), as: UTF8.self)
    }

    // MARK: - reading settings.json

    private static func read(home: URL) throws -> (URL, Data?) {
        let claude = home.appendingPathComponent(".claude")
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: claude.path, isDirectory: &dir), dir.boolValue else {
            throw Problem.noClaude(tilde(claude, home))
        }
        let url = settingsURL(home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return (url, nil) }
        do { return (url, try Data(contentsOf: url)) } catch { throw Problem.unreadable(tilde(url, home)) }
    }

    private static func tilde(_ u: URL, _ home: URL) -> String { u.path.replacingOccurrences(of: home.path, with: "~") }

    /// The statusLine command string, nil if there is no statusLine. Throws for a statusLine without a command string.
    private static func command(in bytes: [UInt8]) throws -> String? {
        guard let o = try? JSONSerialization.jsonObject(with: Data(bytes)) as? [String: Any] else { return nil }
        guard let sl = o["statusLine"] else { return nil }
        guard let c = (sl as? [String: Any])?["command"] as? String else { throw Problem.unknownForm }
        return c
    }

    private static func object(_ bytes: [UInt8], _ url: URL) throws -> JSONText.Object {
        guard (try? JSONSerialization.jsonObject(with: Data(bytes))) is [String: Any], let o = JSONText.object(bytes) else {
            throw Problem.unreadable(url.lastPathComponent)
        }
        return o
    }

    private static func splice(_ b: [UInt8], _ r: Range<Int>, _ s: String) -> [UInt8] {
        var b = b
        b.replaceSubrange(r, with: Array(s.utf8))
        return b
    }

    /// The whitespace before a member on its line ("  " in a two-space file).
    private static func indentation(_ b: [UInt8], _ start: Int) -> String {
        var i = start
        while i > 0, b[i - 1] == 0x20 || b[i - 1] == 0x09 { i -= 1 }
        return String(decoding: b[i..<start], as: UTF8.self)
    }

    /// The bytes to cut so that member `m` and one comma go, and the next member takes its place.
    private static func removal(_ b: [UInt8], _ o: JSONText.Object, _ m: JSONText.Member) -> Range<Int> {
        guard let k = o.members.firstIndex(where: { $0.start == m.start }) else { return m.start..<m.value.upperBound }
        if k + 1 < o.members.count { return m.start..<o.members[k + 1].start }        // up to the next key
        if k > 0 { return o.members[k - 1].value.upperBound..<m.value.upperBound }      // the last one: from the comma before
        return (o.open + 1)..<o.close                                                    // the only one: "{}" again
    }

    /// The new file, checked before anything is written: it parses, every other top-level key is unchanged.
    private static func change(_ url: URL, _ old: Data?, _ new: [UInt8]) throws -> Change {
        let before = old ?? Data("{}".utf8), after = Data(new)
        guard var a = try JSONSerialization.jsonObject(with: before) as? [String: Any],
              var z = try? JSONSerialization.jsonObject(with: after) as? [String: Any] else { throw Problem.unreadable(url.lastPathComponent) }
        let slA = a.removeValue(forKey: "statusLine"), slZ = z.removeValue(forKey: "statusLine")
        guard NSDictionary(dictionary: a).isEqual(to: z) else { throw Problem.unreadable(url.lastPathComponent) }
        return Change(settings: url, old: old, new: after, before: slA.map(pretty), after: slZ.map(pretty))
    }

    private static func pretty(_ v: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: v, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "\(v)" }
        return String(decoding: d, as: UTF8.self)
    }
}

/// Where the top-level members of a JSON object sit in its text, so one member can be changed and every
/// other byte kept. Only used on text JSONSerialization has already accepted; stricter than it about
/// a trailing comma, which Claude Code would refuse.
enum JSONText {
    struct Member { var key: String; var start: Int; var value: Range<Int> }
    struct Object { var open: Int; var close: Int; var members: [Member] }

    static func object(_ b: [UInt8]) -> Object? {
        var i = 0
        func ws() { while i < b.count, b[i] == 0x20 || b[i] == 0x09 || b[i] == 0x0a || b[i] == 0x0d { i += 1 } }
        func string() -> Bool {
            guard i < b.count, b[i] == 0x22 else { return false }
            i += 1
            while i < b.count {
                if b[i] == 0x5c { i += 2; continue }
                i += 1
                if b[i - 1] == 0x22 { return true }
            }
            return false
        }
        func value() -> Bool {
            guard i < b.count else { return false }
            if b[i] == 0x22 { return string() }
            if b[i] == 0x7b || b[i] == 0x5b {
                var depth = 0
                while i < b.count {
                    switch b[i] {
                    case 0x22: if !string() { return false }; continue
                    case 0x7b, 0x5b: depth += 1
                    case 0x7d, 0x5d: depth -= 1; if depth == 0 { i += 1; return true }
                    default: break
                    }
                    i += 1
                }
                return false
            }
            let s = i
            while i < b.count, ![0x2c, 0x7d, 0x5d, 0x20, 0x09, 0x0a, 0x0d].contains(b[i]) { i += 1 }
            return i > s
        }
        ws()
        guard i < b.count, b[i] == 0x7b else { return nil }
        let open = i
        i += 1
        var members: [Member] = [], comma = false
        while true {
            ws()
            guard i < b.count else { return nil }
            if b[i] == 0x7d { return comma ? nil : Object(open: open, close: i, members: members) }
            let start = i
            guard string() else { return nil }
            let key = String(decoding: b[(start + 1)..<(i - 1)], as: UTF8.self)
            ws()
            guard i < b.count, b[i] == 0x3a else { return nil }
            i += 1
            ws()
            let v = i
            guard value() else { return nil }
            members.append(Member(key: key, start: start, value: v..<i))
            ws()
            guard i < b.count else { return nil }
            comma = b[i] == 0x2c
            if comma { i += 1 } else if b[i] != 0x7d { return nil }
        }
    }
}
