import Foundation
import Testing
@testable import TokenPet
import TokenPetAssets

// Titles and achievements (LOGIC.md, "Titles").

@Suite struct TitleLadder {
    @Test func tenRanksClimbingSteadily() {
        let t = Titles.ladder.map(\.tokens)
        #expect(t.count == 10)
        #expect(zip(t, t.dropFirst()).allSatisfy { $0 < $1 })
        #expect(t.first == 100_000)                                  // the first session
        #expect(t[6] == MountainLedger.defaultSize)                   // Taihang gone: on to Wangwu
        #expect(t[8] == 2 * MountainLedger.defaultSize)               // both mountains: heaven is moved
        // the curve at a daily ~10M counted tokens: a title in the first day, the top after months
        let perDay = 10_000_000.0
        #expect(t[1] / perDay < 1)
        #expect((180...400).contains(t.last! / perDay))
    }

    @Test func rankAndProgress() {
        #expect(Titles.rank(0) == -1)
        #expect(Titles.rank(99_999) == -1)
        #expect(Titles.rank(100_000) == 0)
        #expect(Titles.rank(999_999) == 0)
        #expect(Titles.rank(1_000_000) == 1)
        #expect(Titles.rank(5e12) == 9)
        let p = Titles.progress(550_000)!
        #expect(p.next == 1 && abs(p.fraction - 0.5) < 1e-9 && p.left == 450_000)
        #expect(Titles.progress(0)!.next == 0)
        #expect(Titles.progress(3e9) == nil)                          // the top title
    }

    @Test func everyTitleHasItsOwnName() {   // the four translations are checked by Languages.everyStringIsTranslated
        #expect(Set(Titles.ladder.map { $0.name() }).count == 10)
        #expect(Set(Feat.allCases.map(Titles.name)).count == Feat.allCases.count)
    }

    @Test func longestRunOfDays() {
        #expect(Titles.longestRun([]) == 0)
        #expect(Titles.longestRun([5, 3, 4, 4, 9]) == 3)
        #expect(Titles.longestRun(Array(10...16)) == 7)
    }

    @Test func eventDaysInTheLocalCalendar() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let midnight = cal.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        let d = Titles.days([midnight.addingTimeInterval(-60), midnight.addingTimeInterval(60), midnight.addingTimeInterval(120)], cal: cal)
        #expect(d.count == 2 && d[1] == d[0] + 1)
    }
}

@Suite struct TitleBookTests {
    func store() -> UserDefaults {
        let name = "tokenpet-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Seoul")!; return c }
    func at(_ day: Int, _ hour: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))! }
    func dayNo(_ day: Int) -> Int { Titles.day(at(day, 12), cal: cal) }
    func snap(_ st: PetState = .lively, week: Double = 10, weekStart: Date? = nil) -> Snapshot {
        var s = Snapshot(known: true, state: st)
        s.week = Meter(pct: week, resetsAt: nil)
        s.weekStart = weekStart
        s.resting = st == .resting
        return s
    }

    @Test func oneCelebrationPerRankAndItSurvivesARestart() {
        let d = store()
        var b = TitleBook.load(d)
        #expect(b.observe(TitleInputs(lifetime: 50_000, snap: snap(), now: at(3, 12)), cal: cal) == [])
        // the first run finds a week of logs: only the highest rank reached is celebrated
        #expect(b.observe(TitleInputs(lifetime: 12_000_000, snap: snap(), now: at(3, 12)), cal: cal) == [.rank(2)])
        #expect(b.observe(TitleInputs(lifetime: 12_000_001, snap: snap(), now: at(3, 12)), cal: cal) == [])
        var again = TitleBook.load(d)                                 // app restarted
        #expect(again.seen == 2)
        #expect(again.observe(TitleInputs(lifetime: 12_000_002, snap: snap(), now: at(3, 13)), cal: cal) == [])
        #expect(again.observe(TitleInputs(lifetime: 40_000_000, snap: snap(), now: at(3, 14)), cal: cal) == [.rank(3)])
    }

    @Test func aFullCarrierAndTheDawnReset() {
        var b = TitleBook.load(store())
        #expect(b.observe(TitleInputs(lifetime: 0, snap: snap(.resting), now: at(3, 15)), cal: cal) == [.feat(.fullCarrier)])
        #expect(b.observe(TitleInputs(lifetime: 0, snap: snap(.resting), now: at(3, 16)), cal: cal) == [])   // once
        #expect(b.observe(TitleInputs(lifetime: 0, snap: snap(.morning), now: at(3, 9)), cal: cal) == [])    // a reset, but not at dawn
        #expect(b.observe(TitleInputs(lifetime: 0, snap: snap(.morning), now: at(4, 4)), cal: cal) == [.feat(.dawnReset)])
        var unknown = snap(.resting); unknown.known = false
        var c = TitleBook.load(store())
        #expect(c.observe(TitleInputs(lifetime: 0, snap: unknown, now: at(3, 15)), cal: cal) == [])          // no limits, no claims
    }

    @Test func sevenDaysInARowAndTwoAIsOnOneDay() {
        var b = TitleBook.load(store())
        #expect(b.observe(TitleInputs(lifetime: 0, snap: snap(), sourceDays: [(1...6).map(dayNo)], now: at(6, 20)), cal: cal) == [])
        // Codex on day 7 only: the streak counts any AI, and two AIs share no day yet
        #expect(b.observe(TitleInputs(lifetime: 0, snap: snap(), sourceDays: [[], [dayNo(7)]], now: at(7, 20)), cal: cal) == [.feat(.streak7)])
        #expect(b.observe(TitleInputs(lifetime: 0, snap: snap(), sourceDays: [[dayNo(7)], [dayNo(7)]], now: at(7, 21)), cal: cal) == [.feat(.twoAIs)])
    }

    @Test func aKeptWeekNeedsTheWeekToEndWithoutRunningOut() {
        let d = store()
        var b = TitleBook.load(d)
        let w1 = at(2, 9), w2 = w1.addingTimeInterval(Limits.weekLength), w3 = w2.addingTimeInterval(Limits.weekLength)
        #expect(b.observe(TitleInputs(lifetime: 0, snap: snap(week: 100, weekStart: w1), now: at(5, 12)), cal: cal) == [])
        // the reset time wobbles by seconds between readings: still the same week
        #expect(b.observe(TitleInputs(lifetime: 0, snap: snap(week: 20, weekStart: w1.addingTimeInterval(3)), now: at(5, 13)), cal: cal) == [])
        // week 1 ran out, so week 2 starting earns nothing
        #expect(b.observe(TitleInputs(lifetime: 0, snap: snap(week: 1, weekStart: w2), now: at(9, 10)), cal: cal) == [])
        #expect(b.observe(TitleInputs(lifetime: 0, snap: snap(week: 80, weekStart: w2), now: at(14, 10)), cal: cal) == [])
        var again = TitleBook.load(d)                                 // restarted mid-week: the watch carries over
        #expect(again.weekStart == w2 && !again.weekFull)
        #expect(again.observe(TitleInputs(lifetime: 0, snap: snap(week: 2, weekStart: w3), now: at(16, 10)), cal: cal) == [.feat(.weekKept)])
        #expect(TitleBook.load(d).feats[.weekKept] == at(16, 10))
    }

    @Test func lifetimeAddsUpEveryMountain() {
        let d = store()
        d.set(1000.0, forKey: "mountain.size")
        var m = MountainLedger.load(d)
        m.absorb([LogScanner.Event(time: Date(timeIntervalSince1970: 1), tokens: 1300, output: 0)])
        #expect(m.lifetime == 1300)
        m.nextMountain()
        #expect(m.lifetime == 1300)                                   // moving on to the next mountain keeps the total
    }
}
