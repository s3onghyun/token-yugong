import AppKit

// "Send feedback…": opens a prefilled GitHub issue (or, once an address is set, an email) in the
// browser or mail app. The app itself sends nothing: no request, no telemetry. The prefill holds
// version facts only (app, macOS, Mac model, which AIs the family watches), never a path, a user or
// host name, or anything from the user's work.

/// The address "Send an email instead" writes to. Empty: that choice is hidden and the menu says an
/// email option comes later. Setting it is the whole change needed to turn the email path on.
enum FeedbackContact {
    static let email = ""
}

enum Feedback {
    static let newIssue = URL(string: "https://github.com/s3onghyun/token-yugong/issues/new")!
    /// GitHub turns away very long prefill URLs; the body stays well under this.
    static let maxBody = 2000
    static let title = "Feedback: "

    /// The facts the prefill carries. Every field is cleaned by `clean`, so nothing else gets in.
    struct Environment: Equatable {
        var app: String
        var build: String
        var macOS: String
        var model: String?
        var agents: [String]
    }

    enum Choice: Hashable { case github, email(String) }

    /// The menu's choices: GitHub always, email only when an address is set.
    static func choices(email: String = FeedbackContact.email) -> [Choice] {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.isEmpty ? [.github] : [.github, .email(e)]
    }

    /// This Mac and this app, read now.
    static func current(family: Family = Family.load()) -> Environment {
        let info = Bundle.main.infoDictionary
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return Environment(app: info?["CFBundleShortVersionString"] as? String ?? "dev",
                           build: info?["CFBundleVersion"] as? String ?? "dev",
                           macOS: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                           model: hardwareModel(),
                           agents: agents(family))
    }

    /// "Mac14,2": the model identifier, not the Mac's name (which often holds the owner's name).
    static func hardwareModel() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buf, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The watched AIs by product name, Grandpa's first.
    static func agents(_ family: Family) -> [String] {
        Role.allCases.compactMap { family.roles[$0] }.map { p in
            switch p {
            case .claude: return "Claude Code"
            case .codex: return "Codex"
            case .gemini: return "Gemini CLI"
            case .openai: return "OpenAI API"
            case .deepseek: return "DeepSeek API"
            }
        }
    }

    /// Keeps letters, digits and ". , ( ) + -" (what versions and model ids use), at most 40 characters:
    /// a path, an address or a host name cannot pass through a field intact.
    static func clean(_ s: String) -> String {
        let ok = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,()+-")
        return String(s.filter { ok.contains($0) }.prefix(40)).trimmingCharacters(in: .whitespaces)
    }

    /// The issue or email text, in English for the maintainer.
    static func body(_ env: Environment) -> String {
        var lines = ["**What happened?**", "", "", "**What did you expect?**", "", "", "### Environment",
                     "- App: Token Yugong \(clean(env.app)) (build \(clean(env.build)))",
                     "- macOS: \(clean(env.macOS))"]
        if let m = env.model.map(clean), !m.isEmpty { lines.append("- Mac: \(m)") }
        let agents = env.agents.map(clean).filter { !$0.isEmpty }
        if !agents.isEmpty { lines.append("- Agents: \(agents.joined(separator: ", "))") }
        lines += ["", "_Prefilled by the app's Send feedback menu. The app sent nothing; only what you submit here is sent._"]
        return String(lines.joined(separator: "\n").prefix(maxBody))
    }

    /// RFC 3986 unreserved characters only; everything else is percent-encoded (space as %20, never +).
    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? ""
    }

    static func issueURL(_ env: Environment) -> URL {
        URL(string: newIssue.absoluteString + "?title=" + encode(title) + "&body=" + encode(body(env)))!
    }

    static func mailURL(_ env: Environment, to address: String) -> URL? {
        URL(string: "mailto:" + encode(address).replacingOccurrences(of: "%40", with: "@")
            + "?subject=" + encode("Token Yugong " + title) + "&body=" + encode(body(env)))
    }

    static func open(_ choice: Choice) {
        let env = current()
        switch choice {
        case .github: NSWorkspace.shared.open(issueURL(env))
        case .email(let a): if let u = mailURL(env, to: a) { NSWorkspace.shared.open(u) }
        }
    }

    // MARK: - Words shown in the menus

    static var menuTitle: String { L.t("Send feedback…", "의견 보내기…", "フィードバックを送る…", "发送反馈…") }
    static var nothingSent: String {
        L.t("Opens your browser or mail app; nothing is sent until you send it.",
            "브라우저나 메일 앱이 열려요. 직접 보내기 전에는 아무것도 전송되지 않아요.",
            "ブラウザーかメールアプリが開きます。自分で送るまで何も送信されません。",
            "将打开浏览器或邮件应用；在你亲自发送之前不会发送任何内容。")
    }
    static var emailLater: String {
        L.t("An email option comes in a later version.",
            "이메일로 보내기는 다음 버전에서 추가돼요.",
            "メールで送る方法は今後のバージョンで追加されます。",
            "邮件反馈将在以后的版本中提供。")
    }
    static func label(_ c: Choice) -> String {
        switch c {
        case .github: return L.t("Open a GitHub issue", "GitHub 이슈 열기", "GitHub の Issue を開く", "在 GitHub 上提 Issue")
        case .email: return L.t("Send an email instead", "대신 이메일 보내기", "代わりにメールを送る", "改为发送邮件")
        }
    }

    /// The same choices as an AppKit submenu (the mini window's right-click menu).
    static func submenu() -> NSMenuItem {
        let item = NSMenuItem(title: menuTitle, action: nil, keyEquivalent: "")
        let m = NSMenu()
        let note = NSMenuItem(title: nothingSent, action: nil, keyEquivalent: ""); note.isEnabled = false
        m.addItem(note)
        for c in choices() {
            let i = NSMenuItem(title: label(c), action: #selector(MenuTarget.run(_:)), keyEquivalent: "")
            i.target = MenuTarget.shared; i.representedObject = c
            m.addItem(i)
        }
        if choices().count == 1 {
            let later = NSMenuItem(title: emailLater, action: nil, keyEquivalent: ""); later.isEnabled = false
            m.addItem(later)
        }
        item.submenu = m
        return item
    }

    final class MenuTarget: NSObject {
        static let shared = MenuTarget()
        @objc func run(_ i: NSMenuItem) { if let c = i.representedObject as? Choice { Feedback.open(c) } }
    }
}
