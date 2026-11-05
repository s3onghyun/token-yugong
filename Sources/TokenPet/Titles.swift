import Foundation

// Titles: a ladder of ranks earned by every token Grandpa has ever shovelled (the mountain counter),
// plus a few side achievements. Rules in LOGIC.md ("Titles"). The ladder and the achievements are
// pure data and pure functions of what the app observes; TitleBook keeps what was earned on this Mac.

/// A rank on the ladder: reached once `tokens` have been carried in all.
struct Rank {
    let tokens: Double
    let name: () -> String   // computed when drawn, so a language change shows at once
}

/// The side achievements.
enum Feat: String, CaseIterable {
    case fullCarrier, streak7, weekKept, twoAIs, dawnReset
}

enum Titles {
    /// Roughly x3 at first, then by whole mountains (1 mountain = 1B tokens): the first title comes in the
    /// first session, the master after months. At ~10M counted tokens a day (a daily Claude Code user;
    /// cache writes count) that is: 1M the first afternoon, 100M in ~10 days, 1B (Taihang gone) in ~3 months,
    /// 3B in ~10 months. See LOGIC.md for the table.
    static let ladder: [Rank] = [
        Rank(tokens: 100_000) { L.t("Grandson with a Shovel", "삽 든 손주", "シャベルを持った孫", "拿铲的孙子") },
        Rank(tokens: 1_000_000) { L.t("Carrier Bearer", "지게꾼", "背負子かつぎ", "背架工") },
        Rank(tokens: 10_000_000) { L.t("Stone Breaker", "돌 깨는 일꾼", "石割り職人", "碎石工") },
        Rank(tokens: 40_000_000) { L.t("Basket Master", "삼태기 장인", "もっこの名人", "箕畚匠人") },
        Rank(tokens: 100_000_000) { L.t("Hauler to the Bohai Sea", "발해까지 나르는 자", "渤海まで運ぶ者", "运土到渤海的人") },
        Rank(tokens: 300_000_000) { L.t("Carver of Mount Taihang", "태행산을 깎는 자", "太行山を削る者", "削平太行山的人") },
        Rank(tokens: 1_000_000_000) { L.t("Mover of Mount Wangwu", "왕옥산을 옮기는 자", "王屋山を移す者", "搬移王屋山的人") },
        Rank(tokens: 1_500_000_000) { L.t("Heir of Yugong", "우공의 후계자", "愚公の後継ぎ", "愚公的传人") },
        Rank(tokens: 2_000_000_000) { L.t("One Who Moved Heaven", "하늘도 감동한 자", "天をも動かした者", "感动上天的人") },
        Rank(tokens: 3_000_000_000) { L.t("Yugong Who Moved the Mountains", "산을 옮긴 우공", "山を移した愚公", "移山的愚公") },
    ]

    /// The highest rank reached with `tokens` in all; -1 = none yet.
    static func rank(_ tokens: Double) -> Int { (ladder.lastIndex { tokens >= $0.tokens }) ?? -1 }

    /// Progress from the current rank to the next, 0...1; nil at the top.
    static func progress(_ tokens: Double) -> (next: Int, fraction: Double, left: Double)? {
        let r = rank(tokens), n = r + 1
        guard n < ladder.count else { return nil }
        let from = r < 0 ? 0 : ladder[r].tokens, to = ladder[n].tokens
        return (n, max(0, min(1, (tokens - from) / (to - from))), max(0, to - tokens))
    }

    static func name(_ f: Feat) -> String {
        switch f {
        case .fullCarrier: return L.t("Full Carrier", "지게 가득", "背負子いっぱい", "背架装满")
        case .streak7: return L.t("Seven Days of Digging", "이레 연속 삽질", "七日続けて掘る", "连挖七天")
        case .weekKept: return L.t("Kept to the Week", "주간 한도 지킴이", "週間リミットを守った", "守住每周额度")
        case .twoAIs: return L.t("Two Shovels", "두 삽으로", "二本のシャベル", "两把铲子")
        case .dawnReset: return L.t("Up for the Dawn Reset", "새벽 리셋을 지켜본 자", "夜明けのリセットを見届けた", "守到黎明重置")
        }
    }

    static func detail(_ f: Feat) -> String {
        switch f {
        case .fullCarrier: return L.t("A limit ran out and Grandpa had to rest.", "한도를 다 써서 할아버지가 쉬었어요.",
                                        "リミットを使い切って、おじいさんが休みました。", "额度用完了，爷爷只好歇一歇。")
        case .streak7: return L.t("Tokens moved on seven days in a row.", "7일 연속으로 토큰을 옮겼어요.",
                                    "7日続けてトークンを運びました。", "连续七天都在搬 token。")
        case .weekKept: return L.t("A whole week ended without running out of the weekly limit.", "주간 한도를 다 쓰지 않고 한 주를 마쳤어요.",
                                     "週間リミットを使い切らずに一週間を終えました。", "一整周都没有用完每周额度。")
        case .twoAIs: return L.t("Two AIs (Claude Code, Codex, Gemini CLI) worked on the same day.", "두 AI(Claude Code·Codex·Gemini CLI)가 같은 날 일했어요.",
                                   "二つの AI（Claude Code・Codex・Gemini CLI）が同じ日に働きました。", "两个 AI（Claude Code、Codex、Gemini CLI）在同一天干活。")
        case .dawnReset: return L.t("Still at it when a limit reset before 6 a.m.", "새벽 6시 전에 한도가 리셋될 때 깨어 있었어요.",
                                      "朝6時前にリミットがリセットされたとき、まだ起きていました。", "清晨 6 点前额度重置时还在干活。")
        }
    }

    /// A day number for the local date of `t` in `cal`: consecutive dates differ by 1.
    /// (`Calendar.ordinality(of: .day, in: .era)` ignores the calendar's time zone, so it is not used.)
    static func day(_ t: Date, cal: Calendar = .current) -> Int {
        let c = cal.dateComponents([.year, .month, .day], from: t)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        return Int(((utc.date(from: c)?.timeIntervalSince1970 ?? 0) / 86400).rounded())
    }

    /// The day numbers of `times`, one lookup per distinct minute: cheap for many events.
    static func days(_ times: [Date], cal: Calendar = .current) -> [Int] {
        var first: [Int: Date] = [:]
        for t in times { let m = Int(t.timeIntervalSince1970 / 60); if first[m] == nil { first[m] = t } }
        return Set(first.values.map { day($0, cal: cal) }).sorted()
    }

    /// The longest run of consecutive days in `days` (day numbers).
    static func longestRun(_ days: [Int]) -> Int {
        var best = 0, run = 0, prev: Int?
        for d in Set(days).sorted() {
            run = prev.map { d == $0 + 1 } == true ? run + 1 : 1
            best = max(best, run); prev = d
        }
        return best
    }
}

/// What the app saw this refresh, for the achievements.
struct TitleInputs {
    var lifetime: Double                 // every token carried, all mountains
    var snap: Snapshot
    var sourceDays: [[Int]] = []         // per local CLI (Claude Code, Codex, Gemini CLI): the days it has events
    var now: Date
}

/// Something newly earned, to celebrate.
enum Award: Equatable {
    case rank(Int)
    case feat(Feat)
}

/// What was earned on this Mac, kept in UserDefaults next to the mountain.
struct TitleBook {
    var feats: [Feat: Date] = [:]
    var days: [Int] = []          // days with tokens (recent ones), for the 7-day streak
    var seen = -1                 // the highest rank already celebrated
    var weekStart: Date?          // the weekly window being watched
    var weekFull = false          // it ran out
    var finaleSeen = false        // the #10 finale played once (it can be replayed from the titles window)
    var store: UserDefaults = Prefs.store

    static func load(_ d: UserDefaults = Prefs.store) -> TitleBook {
        var b = TitleBook(store: d)
        for (k, v) in d.dictionary(forKey: "titles.feats") ?? [:] {
            if let f = Feat(rawValue: k), let t = v as? Double { b.feats[f] = Date(timeIntervalSince1970: t) }
        }
        b.days = d.array(forKey: "titles.days") as? [Int] ?? []
        b.seen = d.object(forKey: "titles.seen") as? Int ?? -1
        b.weekStart = (d.object(forKey: "titles.week.start") as? Double).map(Date.init(timeIntervalSince1970:))
        b.weekFull = d.bool(forKey: "titles.week.full")
        b.finaleSeen = d.bool(forKey: "titles.finale")
        return b
    }

    func save() {
        let d = store
        d.set(Dictionary(uniqueKeysWithValues: feats.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) }), forKey: "titles.feats")
        d.set(days, forKey: "titles.days")
        d.set(seen, forKey: "titles.seen")
        d.set(weekStart?.timeIntervalSince1970, forKey: "titles.week.start")
        d.set(weekFull, forKey: "titles.week.full")
        d.set(finaleSeen, forKey: "titles.finale")
    }

    /// The finale is due once the top title is reached, until it has been watched.
    func finaleDue(_ lifetime: Double) -> Bool { Titles.rank(lifetime) == Titles.ladder.count - 1 && !finaleSeen }

    /// Records what `i` shows and returns what is newly earned: at most one rank (the highest, even after
    /// skipping several, e.g. on the first run with a full log), then any new achievements.
    mutating func observe(_ i: TitleInputs, cal: Calendar = .current) -> [Award] {
        var out: [Award] = []
        let r = Titles.rank(i.lifetime)
        if r > seen { seen = r; out.append(.rank(r)) }
        func earn(_ f: Feat, _ yes: Bool) {
            if yes && feats[f] == nil { feats[f] = i.now; out.append(.feat(f)) }
        }
        let s = i.snap
        earn(.fullCarrier, s.known && s.resting)
        // a new weekly window: the one before it was kept if it never ran out while we watched
        if s.known, let ws = s.weekStart {
            // reset times wobble by seconds between readings: only a start a day later is a new week
            if let old = weekStart, ws.timeIntervalSince(old) > 86400 { earn(.weekKept, !weekFull); weekFull = false; weekStart = ws }
            if weekStart == nil { weekStart = ws }
            if (s.week?.pct ?? 0) >= 100 { weekFull = true }
        }
        let today = Titles.day(i.now, cal: cal)
        days = Array(Set(days + i.sourceDays.flatMap { $0 }).filter { $0 > today - 30 && $0 <= today }).sorted()
        earn(.streak7, Titles.longestRun(days) >= 7)
        var perDay: [Int: Int] = [:]
        for src in i.sourceDays { for d in Set(src) { perDay[d, default: 0] += 1 } }
        earn(.twoAIs, perDay.values.contains { $0 >= 2 })
        earn(.dawnReset, s.known && s.state == .morning && cal.component(.hour, from: i.now) < 6)
        save()
        return out
    }
}
