import Foundation
import Testing
@testable import TokenPet

@Suite struct ClaudeAccountTests {
    @Test func masksTheSignedInEmail() {
        #expect(ClaudeAccount.mask("joshua@infograb.io") == "jo***@infograb.io")
        #expect(ClaudeAccount.mask("a@example.com") == "a***@example.com")
        #expect(ClaudeAccount.mask("not-an-email") == nil)
    }

    @Test func decodesAndHashesTheSignedInAccount() {
        let account = ClaudeAccount.decode(Data(#"{"oauthAccount":{"accountUuid":"account-1","emailAddress":"joshua@infograb.io"}}"#.utf8))
        #expect(account.maskedEmail == "jo***@infograb.io")
        #expect(account.id == "07e998012c11")  // matches bridge/statusline-bridge.sh's SHA-256 prefix
    }

    @Test func comparesOnlyKnownAccountIdentities() {
        let account = ClaudeAccount.decode(Data(#"{"oauthAccount":{"accountUuid":"account-1"}}"#.utf8))
        #expect(!account.differs(from: account.id))
        #expect(account.differs(from: "another-account"))
        #expect(!account.differs(from: nil))
        #expect(!ClaudeAccount().differs(from: "another-account"))
    }
}

@Suite struct AccountReadingsTests {
    let now = Date(timeIntervalSince1970: 1_793_700_000)
    let alpha = "aaaa11112222", beta = "bbbb33334444", gamma = "cccc55556666"

    func reading(_ key: String?, five: Double, week: Double, at: TimeInterval = 0) -> Reading {
        Reading(five: Meter(pct: five, resetsAt: now + 5 * hour),
                week: Meter(pct: week, resetsAt: now + 7 * day), at: now + at, account: key)
    }

    @Test func readingsStayIndependentAndSelectionChangesTheDisplayImmediately() {
        var accounts = AccountReadings()
        let a = reading(alpha, five: 24, week: 31)
        let b = reading(beta, five: 72, week: 48, at: 60)
        accounts.takeClaude(a)
        accounts.takeClaude(b)
        #expect(accounts.selectedClaude == a) // first identified key is saved, not replaced by new input
        accounts.select(.claude(beta))
        #expect(accounts.selectedClaude == b)
        #expect(BarText.percent.text(Logic.evaluate(main: accounts.selectedClaude, now: now), cutscene: false, now: now) == "72%")
        accounts.select(.claude(alpha))
        #expect(BarText.percent.text(Logic.evaluate(main: accounts.selectedClaude, now: now), cutscene: false, now: now) == "24%")
    }

    @Test func aLoginChangeResetsAnEarlierPickerChoice() {
        var accounts = AccountReadings()
        accounts.syncLogin(alpha)
        accounts.takeClaude(reading(alpha, five: 24, week: 31))
        accounts.takeClaude(reading(beta, five: 72, week: 48, at: 60))
        accounts.select(.claude(alpha))

        accounts.syncLogin(beta)

        #expect(accounts.selected == .claude(beta))
        #expect(accounts.selectedClaude?.week?.pct == 48)
    }

    @Test func pickerChoiceAfterLoginSticksUntilTheNextLoginChange() {
        var accounts = AccountReadings()
        accounts.takeClaude(reading(alpha, five: 24, week: 31))
        accounts.takeClaude(reading(beta, five: 72, week: 48, at: 60))
        accounts.syncLogin(beta)
        accounts.select(.claude(alpha))

        accounts.syncLogin(beta)
        #expect(accounts.selected == .claude(alpha))

        accounts.syncLogin(gamma)
        #expect(accounts.selected == .claude(gamma))
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
        let weeklyOnly = Reading(five: nil,
                                 week: Meter(pct: 55, resetsAt: now + 7 * day),
                                 at: now + 90,
                                 account: alpha)

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
        accounts.select(.claude(beta))
        accounts.setNickname("Work", for: .claude(beta))
        accounts.save(d)
        let restored = AccountReadings.load(d)
        #expect(restored.selected == .claude(beta))
        #expect(restored.nickname(for: .claude(beta)) == "Work")
        d.removePersistentDomain(forName: "TokenPetTests.account-readings")
    }

    @Test func oldRowsAreKeptUntilTheUserDeletesThemAndCodexIsLocal() {
        var accounts = AccountReadings()
        accounts.takeClaude(reading(alpha, five: 24, week: 31, at: -31 * day))
        accounts.takeCodex(Reading(five: Meter(pct: 13, resetsAt: now + hour), week: nil, at: now))
        #expect(accounts.rows(now: now).first(where: { $0.key == .claude(alpha) })?.stale == true)
        #expect(accounts.rows(now: now).first(where: { $0.key == .local })?.reading.five?.pct == 13)
        accounts.remove(.claude(alpha))
        #expect(!accounts.rows(now: now).contains(where: { $0.key == .claude(alpha) }))
    }
}
