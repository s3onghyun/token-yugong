import Foundation
import Testing
@testable import TokenPetAssets
@testable import TokenPet

// LOGIC.md "Family": who watches which AI, the month window of billed APIs, and the connectors.

@Suite struct FamilyRules {
    func store() -> UserDefaults {
        let name = "TokenPetFamilyTest-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func standardFamilyIsClaudeAndCodex() {
        #expect(Family.load(store()) == Family(roles: [.grandpa: .claude, .grandson: .codex]))
    }

    @Test func turnedOffGrandsonStaysOff() {          // the old "show the grandson" setting carries over
        let d = store(); d.set(false, forKey: "showCodex")
        #expect(Family.load(d) == Family(roles: [.grandpa: .claude]))
    }

    @Test func savedFamilyRoundTrips() {
        let d = store()
        let f = Family(roles: [.grandpa: .codex, .son: .gemini, .boy: .openai])
        f.save(d)
        #expect(Family.load(d) == f)
        d.set(["son": "gemini"], forKey: "family")   // no grandpa saved (odd data): the standard family
        #expect(Family.load(d) == .standard)
    }

    @Test func anAIWatchesOneMemberSoTheySwap() {
        let f = Family.standard.assigning(.codex, to: .grandpa)    // Codex was the grandson's
        #expect(f.roles == [.grandpa: .codex, .grandson: .claude])
        let g = f.assigning(.gemini, to: .son)
        #expect(g.roles[.son] == .gemini && g.roles.count == 3)
        #expect(g.assigning(nil, to: .son).roles[.son] == nil)
        #expect(g.assigning(nil, to: .grandpa) == g)              // Grandpa always watches one
        #expect(g.assigning(.gemini, to: .boy).roles == [.grandpa: .codex, .grandson: .claude, .boy: .gemini])   // nobody left behind
    }

    @Test func grandpaCanWatchCodex() {
        let now = weekStart + 10 * hour
        let codex = Reading(five: Meter(pct: 30, resetsAt: now + hour), week: Meter(pct: 20, resetsAt: reset), at: now)
        let s = Logic.evaluate(main: codex, members: [.grandson: nil], now: now)
        #expect(s.known && s.carrier == 0.30 && s.headline == codex.five)
        #expect(s.members[.grandson] == Member(reading: nil, fill: nil))   // assigned, nothing to read: don't know
    }
}

@Suite struct Budgets {
    let utc = TimeZone(identifier: "UTC")!
    // 2026-11-03 01:28 KST = 2026-11-02 16:28 UTC: still November in UTC
    let now = Date(timeIntervalSince1970: 1_793_636_880)
    let nov1 = Date(timeIntervalSince1970: 1_793_491_200), dec1 = Date(timeIntervalSince1970: 1_796_083_200)

    @Test func theMonthIsTheUTCCalendarMonth() {
        #expect(Budget.monthStart(now) == nov1 && Budget.nextMonth(now) == dec1)
        #expect(Budget.monthStart(dec1) == dec1)                                  // the first second belongs to the new month
    }

    @Test func spendAgainstTheBudget() {
        let r = try! #require(Budget.reading(spent: 40, budget: 100, at: now))
        #expect(r.month == Meter(pct: 40, resetsAt: dec1) && r.five == nil && r.week == nil)
        #expect(Budget.reading(spent: 40, budget: 0, at: now) == nil)              // no budget: nothing to fill
        #expect(Budget.reading(spent: 250, budget: 100, at: now)?.month?.pct == 100)
        let s = Logic.evaluate(main: r, now: now)
        #expect(s.carrier == 0.40 && s.daily == nil && s.headline == r.month)      // a month is not a week: no daily share
    }

    @Test func overBudgetRestsUntilNextMonth() {
        let s = Logic.evaluate(main: Budget.reading(spent: 120, budget: 100, at: now), now: now)
        #expect(s.resting && s.wakeAt == dec1 && s.state == .resting)
        let later = Logic.evaluate(main: Budget.reading(spent: 120, budget: 100, at: now), now: dec1 + 60)
        #expect(!later.resting && later.month == Meter(pct: 0, resetsAt: nil) && later.state == .morning)   // a new month
    }

    @Test func openAICostsSumsDollars() throws {
        let page = #"{"object":"page","has_more":true,"next_page":"p2","data":[{"object":"bucket","results":[{"amount":{"value":1.25,"currency":"usd"}},{"amount":{"value":0.5,"currency":"USD"}}]},{"results":[{"amount":{"value":9,"currency":"eur"}},{"amount":{"value":2,"currency":"usd"}}]},{"results":[]}]}"#
        let r = try #require(Budget.openAICosts(Data(page.utf8)))
        #expect(r.usd == 3.75 && r.next == "p2")                                  // other currencies are not added
        #expect(Budget.openAICosts(Data(#"{"has_more":false,"next_page":"x","data":[]}"#.utf8))?.next == nil)
        #expect(Budget.openAICosts(Data("{broken".utf8)) == nil)
    }

    @Test func deepSeekGivesOnlyABalance() {
        let b = #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.00","granted_balance":"10.00","topped_up_balance":"100.00"}]}"#
        #expect(Budget.deepSeekBalance(Data(b.utf8)) == "CNY 110.00")
        #expect(Budget.deepSeekBalance(Data(#"{"balance_infos":[]}"#.utf8)) == nil)
        #expect(Logic.evaluate(main: nil, members: [.son: nil], now: now).members[.son]?.fill == nil)   // its spend: don't know
    }
}

@Suite struct Connectors {
    @Test func geminiRepliesCarryTokens() {
        let file = #"{"sessionId":"x","messages":[{"type":"user","timestamp":"2026-11-02T16:00:00.000Z"},{"type":"gemini","timestamp":"2026-11-02T16:00:03.000Z","model":"m","tokens":{"input":100,"output":20,"cached":40,"thoughts":5,"tool":0,"total":125}},{"type":"info","timestamp":"2026-11-02T16:00:04.000Z"},{"type":"gemini","timestamp":"bad","tokens":{"output":1}}]}"#
        let e = GeminiReader.events(Data(file.utf8))
        #expect(e.count == 1 && e[0].tokens == 125 && e[0].output == 25)            // only well-formed replies
        #expect(GeminiReader.events(Data("{broken".utf8)).isEmpty)
    }

    @Test func geminiReaderScansChatFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tokenpet-gemini-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let chats = root.appendingPathComponent("proj/chats")
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        let ts = Limits.iso.string(from: Date().addingTimeInterval(-60))
        try #"{"messages":[{"type":"gemini","timestamp":"\#(ts)","tokens":{"output":7,"total":70}}]}"#
            .write(to: chats.appendingPathComponent("session-a.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: chats.appendingPathComponent("notes.json"), atomically: true, encoding: .utf8)   // not a session
        let g = GeminiReader(root: root); g.scan()
        #expect(g.events.map(\.tokens) == [70])
        #expect(GeminiReader(root: root.appendingPathComponent("missing")).events.isEmpty)
    }

    @Test func codexCountsInputWithoutTheCache() throws {
        let line = #"{"timestamp":"2026-11-02T16:00:00.000Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":50}}}}"#
        let e = try #require(CodexReader.output(Data(line.utf8)))
        #expect(e.tokens == 250 && e.output == 50)
    }
}

@Suite struct FamilyRoutines {
    @Test func theSonStrikesAndRestsWhenFull() {
        #expect(YugongArt.sonPose(0.5, fill: 0.5) == .lean)
        #expect(YugongArt.sonPose(1.4, fill: 0.5) == .raise)
        #expect(YugongArt.sonPose(1.8, fill: 0.5) == .strike)
        #expect(YugongArt.sonPose(3.5, fill: 0.5) == .lean)                       // loops every 3 s
        #expect(YugongArt.sonPose(1.8, fill: 1) == .rest)
        #expect(YugongArt.sonPose(-0.5, fill: 0.5) == .raise)                     // a clock before zero wraps to 2.5 s: the second wind-up
    }

    @Test func theBoyHopsAndRestsWhenFull() {
        #expect(YugongArt.boyPose(0.2, fill: 0.3) == .carry)
        #expect(YugongArt.boyPose(0.6, fill: 0.3) == .crouch)
        #expect(YugongArt.boyPose(0.9, fill: 0.3) == .hop)
        #expect(YugongArt.boyPose(0.9, fill: 1.2) == .rest)
    }

    @Test func everyPoseDraws() {
        for p in SonPose.allCases { #expect(YugongArt.sonLayer(p, fill: 0.5) != nil) }
        for p in BoyPose.allCases { #expect(YugongArt.boyLayer(p, fill: 0.5) != nil) }
    }
}
