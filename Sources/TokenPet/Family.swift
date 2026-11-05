import Foundation
import Security

// Yugong's household: which AI each family member watches (Settings › Family). The grandfather
// is the main one (the menu bar, the carrier, his state); the others carry their own meters.
// See LOGIC.md "Family".

enum Provider: String, CaseIterable, Identifiable {
    case claude, codex, gemini, openai, deepseek
    var id: String { rawValue }
    var name: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .openai: return "OpenAI API"
        case .deepseek: return "DeepSeek API"
        }
    }
    /// Billed per token through an API key: the meter is money spent against a monthly budget.
    var billed: Bool { self == .openai || self == .deepseek }
}

enum Role: String, CaseIterable, Identifiable {
    case grandpa, son, grandson, boy
    var id: String { rawValue }
    var name: String {
        switch self {
        case .grandpa: return L.t("Grandpa", "할아버지", "おじいさん", "爷爷")
        case .son: return L.t("Son", "아들", "息子", "儿子")
        case .grandson: return L.t("Grandson", "손주", "孫", "孙子")
        case .boy: return L.t("Neighbour's boy", "이웃집 아이", "隣の子", "邻家小孩")
        }
    }
    /// What his meter is drawn as.
    var meter: String {
        switch self {
        case .grandpa: return L.t("carrier", "지게", "背負子", "背架")
        case .son: return L.t("stone heap", "돌 더미", "石の山", "石堆")
        case .grandson: return L.t("basket", "바구니", "かご", "筐")
        case .boy: return L.t("little basket", "삼태기", "小かご", "簸箕")
        }
    }
}

/// Who watches which AI. Grandpa always watches one; the others may watch none.
struct Family: Equatable {
    var roles: [Role: Provider]
    static let standard = Family(roles: [.grandpa: .claude, .grandson: .codex])

    /// Gives `p` to `role`. An AI watches one member at a time: if another member had it, the two
    /// swap. Grandpa cannot be left without one.
    func assigning(_ p: Provider?, to role: Role) -> Family {
        if p == nil && role == .grandpa { return self }
        var r = roles
        let old = r[role]
        if let p, let other = r.first(where: { $0.value == p && $0.key != role })?.key { r[other] = old }
        r[role] = p
        return Family(roles: r)
    }

    static func load(_ d: UserDefaults = Prefs.store) -> Family {
        if let saved = d.dictionary(forKey: "family") as? [String: String] {
            var r: [Role: Provider] = [:]
            for (k, v) in saved { if let role = Role(rawValue: k), let p = Provider(rawValue: v) { r[role] = p } }
            if r[.grandpa] != nil { return Family(roles: r) }
        }
        // before families: the grandson was Codex unless "show the grandson" was turned off
        return (d.object(forKey: "showCodex") as? Bool) == false ? Family(roles: [.grandpa: .claude]) : standard
    }

    func save(_ d: UserDefaults = Prefs.store) {
        d.set(Dictionary(uniqueKeysWithValues: roles.map { ($0.key.rawValue, $0.value.rawValue) }), forKey: "family")
    }
}

// MARK: - Gemini CLI (local chat files; no network, no credentials)

/// Gemini CLI saves each chat in ~/.gemini/tmp/<project>/chats/session-*.json with the tokens of
/// every reply. It saves no limits or reset times, so Gemini's meter is always "don't know";
/// its tokens still count for the shovel speed and the mountain.
final class GeminiReader {
    let root: URL
    private(set) var events: [LogScanner.Event] = []
    private var seen: [String: Date] = [:]

    init(root: URL) { self.root = root }

    func scan(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-7 * 86400)
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { events = []; return }
        var files: [String: Date] = [:]
        for p in projects {
            let chats = p.appendingPathComponent("chats")
            for f in (try? fm.contentsOfDirectory(at: chats, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            where f.lastPathComponent.hasPrefix("session-") && f.pathExtension == "json" {
                if let m = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, m >= cutoff { files[f.path] = m }
            }
        }
        guard files != seen else { return }
        seen = files
        events = files.keys.flatMap { (try? Data(contentsOf: URL(fileURLWithPath: $0))).map(Self.events) ?? [] }
            .filter { $0.time >= cutoff }.sorted { $0.time < $1.time }
    }

    /// The replies of one session file: tokens = its "total", output = output + thoughts.
    static func events(_ data: Data) -> [LogScanner.Event] {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msgs = o["messages"] as? [[String: Any]] else { return [] }
        return msgs.compactMap { m in
            guard m["type"] as? String == "gemini", let t = m["tokens"] as? [String: Any],
                  let time = (m["timestamp"] as? String).flatMap(Limits.iso.date(from:)) else { return nil }
            let out = (t["output"] as? Int ?? 0) + (t["thoughts"] as? Int ?? 0)
            return LogScanner.Event(time: time, tokens: t["total"] as? Int ?? out, output: out)
        }
    }
}

// MARK: - API budgets (OpenAI, DeepSeek)

/// Billed APIs report money, not limits. OpenAI's Costs API gives this month's spend (needs an
/// Admin key); the meter is spend ÷ the monthly budget the user typed in, resetting with the
/// calendar month (UTC, as OpenAI's daily cost buckets are). DeepSeek reports only a balance, so
/// its spend stays "don't know" and the balance is shown as such.
enum Budget {
    static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    static func monthStart(_ now: Date) -> Date { utc.dateInterval(of: .month, for: now)!.start }
    static func nextMonth(_ now: Date) -> Date { utc.dateInterval(of: .month, for: now)!.end }

    /// Sum of USD amounts in one page of /v1/organization/costs, and the next page cursor.
    static func openAICosts(_ data: Data) -> (usd: Double, next: String?)? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let buckets = o["data"] as? [[String: Any]] else { return nil }
        var usd = 0.0
        for b in buckets {
            for r in b["results"] as? [[String: Any]] ?? [] {
                guard let a = r["amount"] as? [String: Any], (a["currency"] as? String)?.lowercased() == "usd",
                      let v = (a["value"] as? NSNumber)?.doubleValue, v.isFinite else { continue }
                usd += v
            }
        }
        let more = (o["has_more"] as? Bool) == true
        return (usd, more ? o["next_page"] as? String : nil)
    }

    /// DeepSeek's /user/balance as text, e.g. "CNY 110.00"; nil when unusable.
    static func deepSeekBalance(_ data: Data) -> String? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let infos = o["balance_infos"] as? [[String: Any]] else { return nil }
        let parts = infos.compactMap { i -> String? in
            guard let c = i["currency"] as? String, let b = i["total_balance"] as? String else { return nil }
            return "\(c) \(b)"
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The month window: spend as a percent of the budget (no budget: nothing to show).
    static func reading(spent: Double, budget: Double, at: Date) -> Reading? {
        guard budget > 0, spent.isFinite, spent >= 0 else { return nil }
        return Reading(five: nil, week: nil, at: at, month: Meter(pct: min(100, spent / budget * 100), resetsAt: nextMonth(at)))
    }
}

/// API keys live only in the login Keychain (never in a file or the settings).
enum Keychain {
    private static func query(_ p: Provider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.yugongpet.api.\(p.rawValue)",
         kSecAttrAccount as String: "api-key"]
    }
    static func key(_ p: Provider) -> String? {
        var q = query(p); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    @discardableResult static func setKey(_ key: String?, for p: Provider) -> Bool {
        SecItemDelete(query(p) as CFDictionary)
        guard let key, !key.isEmpty else { return true }
        var q = query(p); q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}

/// Fetches spend and balances for the billed providers in the family, at most every 15 minutes each.
final class BudgetClient {
    struct State { var spent: Double?; var balance: String?; var problem: Problem?; var at: Date }
    /// Worded when shown, so it follows a language change.
    enum Problem {
        case noKey, rejected, noAnswer(Int)
        var text: String {
            switch self {
            case .noKey: return L.t("no API key yet", "API 키 없음", "API キー未設定", "尚无 API 密钥")
            case .rejected: return L.t("key not accepted", "키가 거부됨", "キーが拒否されました", "密钥被拒绝")
            case .noAnswer(let code): return L.t("no answer (\(code))", "응답 없음 (\(code))", "応答なし (\(code))", "无响应 (\(code))")
            }
        }
    }
    private(set) var state: [Provider: State] = [:]
    private var asked: [Provider: Date] = [:]
    static let every: TimeInterval = 15 * 60

    func refresh(_ providers: [Provider], now: Date = Date(), done: @escaping () -> Void) {
        for p in providers where p.billed && now.timeIntervalSince(asked[p] ?? .distantPast) >= Self.every {
            asked[p] = now
            guard let key = Keychain.key(p) else { state[p] = State(problem: .noKey, at: now); continue }
            fetch(p, key: key, now: now) { [weak self] s in DispatchQueue.main.async { self?.state[p] = s; done() } }
        }
    }

    /// Forget the last answer so the next refresh asks again (after a new key or budget).
    func reset(_ p: Provider) { asked[p] = nil; state[p] = nil }

    private func fetch(_ p: Provider, key: String, now: Date, done: @escaping (State) -> Void) {
        func get(_ url: URL, _ then: @escaping (Data?, Int) -> Void) {
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req) { d, r, _ in then(d, (r as? HTTPURLResponse)?.statusCode ?? 0) }.resume()
        }
        func failed(_ code: Int) -> State {
            State(problem: code == 401 || code == 403 ? .rejected : .noAnswer(code), at: now)
        }
        switch p {
        case .openai:
            var total = 0.0
            func page(_ cursor: String?, _ n: Int) {
                var c = URLComponents(string: "https://api.openai.com/v1/organization/costs")!
                c.queryItems = [URLQueryItem(name: "start_time", value: "\(Int(Budget.monthStart(now).timeIntervalSince1970))"),
                                URLQueryItem(name: "limit", value: "31")] + (cursor.map { [URLQueryItem(name: "page", value: $0)] } ?? [])
                get(c.url!) { d, code in
                    guard code == 200, let d, let r = Budget.openAICosts(d) else { return done(failed(code)) }
                    total += r.usd
                    if let next = r.next, n < 3 { page(next, n + 1) } else { done(State(spent: total, at: now)) }
                }
            }
            page(nil, 0)
        case .deepseek:
            get(URL(string: "https://api.deepseek.com/user/balance")!) { d, code in
                guard code == 200, let d, let b = Budget.deepSeekBalance(d) else { return done(failed(code)) }
                done(State(balance: b, at: now))
            }
        default: break
        }
    }
}
