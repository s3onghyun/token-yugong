import Foundation
import Testing
@testable import TokenPet

@Suite struct AccountReadingsTests {
    let now = Date(timeIntervalSince1970: 1_793_700_000)
    // Two accounts, known by when their weekly limits reset (nil: a reading without a weekly reset)
    var alpha: Date { now + 7 * day }
    var beta: Date { now + 3 * day + 7 * hour }

    func reading(_ weekResets: Date?, five: Double, week: Double, at: TimeInterval = 0) -> Reading {
        Reading(five: Meter(pct: five, resetsAt: now + 5 * hour),
                week: Meter(pct: week, resetsAt: weekResets), at: now + at)
    }

    private struct LegacyPreference: Codable {
        let reading: Reading?
        let id: String?
    }

    @Test func syntheticSnapshotGoldenReplacesInsteadOfMergingWindows() {
        var accounts = AccountReadings()
        let bothWindows = reading(alpha, five: 100, week: 39, at: 60)
        let weeklyOnly = Reading(five: nil, week: Meter(pct: 55, resetsAt: alpha), at: now + 90)

        func golden(_ value: Reading?) -> String {
            let snapshot = Logic.evaluate(main: value, now: now + 90)
            let five = snapshot.five.map { String(Int($0.pct)) } ?? "unknown"
            let week = snapshot.week.map { String(Int($0.pct)) } ?? "unknown"
            let headline = snapshot.headline.map { String(Int($0.pct)) } ?? "unknown"
            return "5h=\(five) week=\(week) headline=\(headline)"
        }

        accounts.takeClaude(bothWindows)
        let before = golden(accounts.selectedClaude)
        accounts.takeClaude(weeklyOnly)
        let after = golden(accounts.selectedClaude)

        #expect(before == "5h=100 week=39 headline=100")
        #expect(after == "5h=unknown week=55 headline=55")
    }

    @Test func legacyPreferenceMigratesOnceToTheKeyedStore() throws {
        let suite = "TokenPetTests.one-time-account-migration"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let legacy = LegacyPreference(reading: reading(alpha, five: 24, week: 31), id: "aaaa11112222")
        d.set(try JSONEncoder().encode(legacy), forKey: "claude.account")

        let migrated = AccountReadings.load(d)

        #expect(migrated.selected == .claude(weekResets: alpha))
        #expect(migrated.selectedClaude?.five?.pct == 24)
        #expect(d.data(forKey: "claude.account") == nil)
        #expect(d.data(forKey: "claude.readings") != nil)
        let reloaded = AccountReadings.load(d)
        #expect(reloaded == migrated)
        d.removePersistentDomain(forName: suite)
    }

    @Test func readingsStayIndependentAndSelectionChangesTheDisplayImmediately() {
        var accounts = AccountReadings()
        let a = reading(alpha, five: 24, week: 31)
        let b = reading(beta, five: 72, week: 48, at: 60)
        accounts.takeClaude(a)
        accounts.takeClaude(b)
        #expect(accounts.selectedClaude == a) // first identified key is saved, not replaced by new input
        accounts.select(.claude(weekResets: beta))
        #expect(accounts.selectedClaude == b)
        #expect(BarText.percent.text(Logic.evaluate(main: accounts.selectedClaude, now: now), cutscene: false, now: now) == "72%")
        accounts.select(.claude(weekResets: alpha))
        #expect(BarText.percent.text(Logic.evaluate(main: accounts.selectedClaude, now: now), cutscene: false, now: now) == "24%")
    }

    @Test func theNewerCaptureOfTheSameWindowWins() {
        var accounts = AccountReadings()
        accounts.takeClaude(reading(alpha, five: 24, week: 31))
        accounts.takeClaude(reading(alpha, five: 19, week: 36, at: 60))
        #expect(accounts.selectedClaude?.five?.pct == 19)
        #expect(accounts.selectedClaude?.week?.pct == 36)
    }

    @Test func aWeeklyResetWithTheSameResetTimeShowsZero() {
        var accounts = AccountReadings()
        accounts.takeClaude(reading(alpha, five: 40, week: 87))
        accounts.takeClaude(reading(alpha, five: 0, week: 0, at: 600)) // reset mid-window; resets_at unchanged
        #expect(accounts.selectedClaude?.week?.pct == 0)
        #expect(BarText.percent.text(Logic.evaluate(main: accounts.selectedClaude, now: now + 600), cutscene: false, now: now + 600) == "0%")
        accounts.takeClaude(reading(alpha, five: 1, week: 1, at: 660))  // and it keeps counting up from there
        #expect(accounts.selectedClaude?.week?.pct == 1)
    }

    @Test func latestSnapshotDoesNotInventAMissingWindow() {
        // Synthetic form of the 2026-11-20 regression: one account first reports both
        // windows, then its newer bridge snapshot reports only its weekly limit.  The menu
        // must show that 5-hour is unknown, never an older 100% value combined with the week.
        var accounts = AccountReadings()
        accounts.takeClaude(reading(alpha, five: 100, week: 39, at: 60))
        let weeklyOnly = Reading(five: nil, week: Meter(pct: 55, resetsAt: alpha), at: now + 90)

        accounts.takeClaude(weeklyOnly)

        #expect(accounts.selectedClaude == weeklyOnly)
        #expect(accounts.selectedClaude?.five == nil)
        #expect(accounts.selectedClaude?.week?.pct == 55)
        #expect(Logic.evaluate(main: accounts.selectedClaude, now: now + 90).daily != nil)
    }

    @Test func anOlderCaptureArrivingLaterDoesNotOverwriteANewerOne() {
        var accounts = AccountReadings()
        accounts.takeClaude(reading(alpha, five: 30, week: 50, at: 60))
        accounts.takeClaude(reading(alpha, five: 20, week: 45))
        #expect(accounts.selectedClaude?.five?.pct == 30)
        #expect(accounts.selectedClaude?.week?.pct == 50)
        #expect(accounts.selectedClaude?.at == now + 60)
    }

    @Test func aStaleSavedMaximumIsCorrectedByTheBridgeReadingItCameFrom() {
        // 0.3.1 saved max(old, new) with the newest capture time, so the saved row can carry the
        // bridge's own captured_at with an older, higher weekly percentage.
        let suite = "TokenPetTests.stale-weekly-max"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let bridge = reading(alpha, five: 0, week: 0, at: 600)
        var stale = bridge
        stale.week?.pct = 87
        var saved = AccountReadings()
        saved.takeClaude(stale)
        saved.save(d)
        var accounts = AccountReadings.load(d)
        accounts.takeClaude(bridge)
        #expect(accounts.selectedClaude?.week?.pct == 0)
        d.removePersistentDomain(forName: suite)
    }

    @Test func unknownClaudeIsSeparateAndNeverAutoSelected() {
        var accounts = AccountReadings()
        let unknown = reading(nil, five: 44, week: 51)
        accounts.takeClaude(unknown)
        #expect(accounts.selected == nil)
        #expect(accounts.unknownClaude == unknown)
        accounts.select(.unknownClaude)
        #expect(accounts.selected == nil)
    }

    @Test func selectionAndNicknameSurviveARestart() {
        let d = UserDefaults(suiteName: "TokenPetTests.account-readings")!
        d.removePersistentDomain(forName: "TokenPetTests.account-readings")
        var accounts = AccountReadings()
        accounts.takeClaude(reading(alpha, five: 24, week: 31))
        accounts.takeClaude(reading(beta, five: 72, week: 48, at: 60))
        accounts.select(.claude(weekResets: beta))
        accounts.setNickname("Work", for: .claude(weekResets: beta))
        accounts.save(d)
        let restored = AccountReadings.load(d)
        #expect(restored.selected == .claude(weekResets: beta))
        #expect(restored.nickname(for: .claude(weekResets: beta)) == "Work")
        d.removePersistentDomain(forName: "TokenPetTests.account-readings")
    }

    @Test func oldRowsAreKeptUntilTheUserDeletesThemAndCodexIsLocal() {
        var accounts = AccountReadings()
        accounts.takeClaude(reading(alpha, five: 24, week: 31, at: -31 * day))
        accounts.takeCodex(Reading(five: Meter(pct: 13, resetsAt: now + hour), week: nil, at: now))
        #expect(accounts.rows(now: now).first(where: { $0.key == .claude(weekResets: alpha) })?.stale == true)
        #expect(accounts.rows(now: now).first(where: { $0.key == .local })?.reading.five?.pct == 13)
        accounts.remove(.claude(weekResets: alpha))
        #expect(!accounts.rows(now: now).contains(where: { $0.key == .claude(weekResets: alpha) }))
    }

    // MARK: an account is known by its own weekly window (root cause: docs in LOGIC.md "Accounts")

    /// The requester's Mac, 2026-11-26: a Max account (5-hour window, weekly reset Wed 22:00) and a
    /// weekly-only account (reset Mon 04:00) answered in parallel sessions. Tagged by a guessed
    /// account hash they shared one row and the menu bar flipped every 30 s.
    @Test func twoAccountsAnsweringInParallelNeverMixInOneRow() {
        var accounts = AccountReadings()
        accounts.takeCodex(Reading(five: Meter(pct: 9, resetsAt: now + hour), week: nil, at: now))
        let max = { (five: Double, at: TimeInterval) in reading(self.alpha, five: five, week: 5, at: at) }
        let weeklyOnly = { (at: TimeInterval) in Reading(five: nil, week: Meter(pct: 65, resetsAt: self.beta), at: self.now + at) }
        accounts.takeClaude(max(13, 0))
        for (i, r) in [weeklyOnly(30), max(13, 60), weeklyOnly(90), max(14, 120), weeklyOnly(150)].enumerated() {
            accounts.takeClaude(r)
            let shown = Logic.evaluate(main: accounts.selectedClaude, now: now + Double(i + 1) * 30)
            #expect(shown.five != nil && shown.week?.pct == 5)   // never the other account's "5h - week 65%"
        }
        #expect(accounts.selectedClaude?.five?.pct == 14)
        #expect(Set(accounts.rows(now: now).map(\.key)) == [.claude(weekResets: alpha), .claude(weekResets: beta), .local])
        #expect(accounts.codex?.five?.pct == 9)
    }

    /// `/login` while a session stays open: its next answer is the other account's, so it lands
    /// in that account's row. The shown account changes only when the user picks it.
    @Test func aLoginSwitchMidSessionMovesItsAnswersToTheOtherAccount() {
        var accounts = AccountReadings()
        accounts.takeClaude(reading(alpha, five: 40, week: 70))
        accounts.takeClaude(reading(beta, five: 2, week: 10, at: 60))   // same session, after /login
        #expect(accounts.selectedClaude?.week?.pct == 70)
        #expect(accounts.rows(now: now).first { $0.key == .claude(weekResets: beta) }?.reading.week?.pct == 10)
        accounts.select(.claude(weekResets: beta))
        #expect(accounts.selectedClaude?.week?.pct == 10)
        accounts.takeClaude(reading(alpha, five: 41, week: 71, at: 120)) // an old session still on the first account
        #expect(accounts.selectedClaude?.week?.pct == 10)
    }

    /// A week ends: the next weekly window resets exactly a week later, so it is the same account.
    @Test func aWeeklyRolloverKeepsTheAccount() {
        var accounts = AccountReadings()
        accounts.takeClaude(reading(alpha, five: 60, week: 99))
        let next = Reading(five: Meter(pct: 1, resetsAt: alpha + 5 * hour), week: Meter(pct: 0, resetsAt: alpha + 7 * day), at: alpha + 60)
        accounts.takeClaude(next)
        #expect(accounts.selectedClaude == next)
        #expect(accounts.rows(now: alpha).count == 1)
        #expect(AccountKey.claude(weekResets: alpha + 7 * day + 20) == .claude(weekResets: alpha))   // seconds of jitter
    }

    /// 0.3.7 and older keyed rows by a guessed account hash, so a saved row could hold another
    /// account's numbers. Loading re-keys every row by its own reading; the selection and the
    /// nickname follow the row the user saw.
    @Test func savedHashRowsMoveToTheirReadingsWeeklyWindow() throws {
        let suite = "TokenPetTests.rekey-hash-rows"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        func json(_ r: Reading) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) }
        let saved: [String: Any] = [
            "store": ["values": ["claude:aaaa11112222": try json(reading(alpha, five: 20, week: 30)),
                                 "claude:bbbb33334444": try json(reading(alpha, five: 22, week: 31, at: 60)),   // the guessed hash was wrong
                                 "claude:untagged": try json(reading(beta, five: 1, week: 65, at: 30))],
                      "nicknames": ["claude:aaaa11112222": "Work"]],
            "selected": ["value": "claude:aaaa11112222"],
        ]
        d.set(try JSONSerialization.data(withJSONObject: saved), forKey: "claude.readings")
        let loaded = AccountReadings.load(d)
        #expect(loaded.selected == .claude(weekResets: alpha))
        #expect(loaded.selectedClaude?.week?.pct == 31)      // the newer of the two rows for that window
        #expect(loaded.nickname(for: .claude(weekResets: alpha)) == "Work")
        #expect(Set(loaded.rows(now: now).map(\.key)) == [.claude(weekResets: alpha), .claude(weekResets: beta)])
        #expect(AccountReadings.load(d) == loaded)
        d.removePersistentDomain(forName: suite)
    }
}
