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

// Switching the Claude account (LOGIC.md "Another account"), as first read on 2026-11-03: the old account
// hit its 5-hour limit, /login switched to another account, and readings with only a weekly window kept
// coming into the same bridge file. (Corrected the next morning, `AccountSwitchMorning` below: those were
// the old account's numbers, held by idle sessions, its 5-hour window dropped because it had reset.)

@Suite struct AccountSwitch {
    let oldWeek = Date(timeIntervalSince1970: 1_793_797_200)      // the old account's week resets Wed 22:00 KST
    let newWeek = Date(timeIntervalSince1970: 1_794_164_400)      // the new one's Mon 04:00 KST
    let fiveReset = Date(timeIntervalSince1970: 1_793_700_600)    // the old account's used-up 5 hours
    let login = Date(timeIntervalSince1970: 1_793_701_659)        // 19:27 KST
    func old(_ at: Date, five: Double = 99) -> Reading {
        Reading(five: Meter(pct: five, resetsAt: fiveReset), week: Meter(pct: 34, resetsAt: oldWeek), at: at)
    }
    func new(_ at: Date) -> Reading { Reading(five: nil, week: Meter(pct: 37, resetsAt: newWeek), at: at) }

    @Test func theFirstAccountIsTakenAsIs() {
        var a = Accounts()
        #expect(a.take(old(login - hour)) == old(login - hour) && a.switchedAt == nil)
    }

    @Test func aNewWeeklyResetIsAnotherAccount() {
        var a = Accounts()
        _ = a.take(old(login - hour))
        let r = a.take(new(login + 60))
        #expect(r == new(login + 60))                  // nothing of the old account's 5 hours is carried over
        #expect(a.switchedAt == login + 60 && a.previous == oldWeek && a.week == newWeek)
    }

    // the bug: an old session answered after the /login and the bridge file went back to the old account
    @Test func theOldAccountsSessionsAreIgnored() {
        var a = Accounts()
        _ = a.take(old(login - hour))
        _ = a.take(new(login + 60))
        #expect(a.take(old(login + 120, five: 100)) == new(login + 60))
        #expect(a.take(new(login + 600)) == new(login + 600) && a.switchedAt == login + 60)
    }

    // switched back: the new account has gone quiet while the old one is in use again
    @Test func aQuietAccountGivesWayToTheOneInUse() {
        var a = Accounts()
        _ = a.take(old(login - hour))
        _ = a.take(new(login + 60))
        let back = login + 60 + Accounts.quiet + 1
        #expect(a.take(old(back)) == old(back) && a.switchedAt == back && a.previous == newWeek)
    }

    @Test func theNextWeekIsTheSameAccount() {
        var a = Accounts()
        _ = a.take(new(newWeek - hour))
        let next = Reading(five: nil, week: Meter(pct: 1, resetsAt: newWeek + Limits.weekLength), at: newWeek + hour)
        #expect(a.take(next) == next && a.switchedAt == nil)
    }

    // two sessions of one account: one idle (its 5-hour window dropped, its percent older)
    @Test func sessionsOfOneAccountAreMerged() {
        var a = Accounts()
        _ = a.take(old(login - hour, five: 60))
        let idle = Reading(five: nil, week: Meter(pct: 30, resetsAt: oldWeek), at: login - 50 * 60)
        #expect(a.take(idle) == Reading(five: Meter(pct: 60, resetsAt: fiveReset), week: Meter(pct: 34, resetsAt: oldWeek), at: login - 50 * 60))
        let laterWindow = Reading(five: Meter(pct: 2, resetsAt: fiveReset + 5 * hour), week: Meter(pct: 35, resetsAt: oldWeek), at: fiveReset + 60)
        #expect(a.take(laterWindow) == laterWindow)
    }

    @Test func noWeeklyWindowCannotTellAccountsApart() {
        var a = Accounts()
        _ = a.take(new(login))
        let fiveOnly = Reading(five: Meter(pct: 5, resetsAt: login + hour), week: nil, at: login + 60)
        #expect(a.take(fiveOnly)?.five == fiveOnly.five && a.switchedAt == nil)
    }

    // the old account's limit hits: the ones before the switch and the old sessions' retries after it
    @Test func theOldAccountsLimitHitsAreNotTheNewOnes() {
        let before = Limits.Hit(time: login - 1800, week: false, resetsAt: fiveReset + 3 * hour)
        let retry = Limits.Hit(time: login + 300, week: false, resetsAt: fiveReset + 3 * hour)
        let r = new(login + 200)
        #expect(Limits.apply([before], to: r, lastAnswer: nil, now: login + 400, switchedAt: login + 60) == r)
        #expect(Limits.apply([retry], to: new(login + 400), lastAnswer: nil, now: login + 500, switchedAt: login + 60) == new(login + 400))
        #expect(Limits.apply([retry], to: r, lastAnswer: nil, now: login + 500, switchedAt: login + 60) == r)   // logged after the newest reading
        // a retry the new account's reading shows as another window
        let fiveNew = Reading(five: Meter(pct: 20, resetsAt: login + 2 * hour), week: nil, at: login + 400)
        #expect(Limits.apply([retry], to: fiveNew, lastAnswer: nil, now: login + 500, switchedAt: login + 60) == fiveNew)
        // the new account's own hit still counts
        let own = Limits.Hit(time: login + 300, week: true, resetsAt: newWeek)
        #expect(Limits.apply([own], to: r, lastAnswer: nil, now: login + 400, switchedAt: login + 60)?.week?.pct == 100)
    }

    // a restart keeps which account is current and its numbers, so an old session's write is still ignored
    @Test func theAccountSurvivesARestart() {
        let d = UserDefaults(suiteName: "TokenPetTests.accounts")!
        d.removePersistentDomain(forName: "TokenPetTests.accounts")
        var a = Accounts()
        _ = a.take(old(login - hour))
        _ = a.take(new(login + 60))
        a.save(d)
        var b = Accounts.load(d)
        #expect(b == a)
        #expect(b.take(old(login + 120)) == new(login + 60))
        #expect(b.take(new(login + 180)) == new(login + 180) && b.switchedAt == login + 60)
        d.removePersistentDomain(forName: "TokenPetTests.accounts")
    }
}

// 2026-11-04 on this Mac, from the logs, ~/.claude.json and the Claude Code 2.1.318 binary. The /login at
// 19:27 the night before went from a Max account (M) to a Team account (T). The "weekly-only" numbers
// seen after it (37%, week resets Mon 04:00, no 5-hour window) were M's, from an idle session: M's 5-hour
// window had reset at 19:10 and Claude Code drops a window from the status line once it resets. Overnight
// T's own 5-hour window reset (00:10) the same way, and Yugong took T for an account with only a weekly
// limit ("No 5-hour limit on this account") and the wife came to ask about a change of plan.
@Suite struct AccountSwitchMorning {
    let hour: TimeInterval = 3600
    let tWeek = Date(timeIntervalSince1970: 1_793_797_200)   // T's week resets Wed 22:00 KST
    let mWeek = Date(timeIntervalSince1970: 1_794_164_400)   // M's Mon 04:00 KST
    let login = Date(timeIntervalSince1970: 1_793_701_659)   // 19:27 KST
    let tFive = Date(timeIntervalSince1970: 1_793_718_600)   // T's 5 hours reset 00:10 KST
    let morningFive = Date(timeIntervalSince1970: 1_793_760_000)   // 11:40 KST
    let T = "aaaa11112222", M = "bbbb33334444"                // stand-ins for the bridge's hashes

    func team(_ at: Date, five: Meter?, week: Double = 27, tag: String?) -> Reading {
        Reading(five: five, week: Meter(pct: week, resetsAt: tWeek), at: at, account: tag)
    }
    func max(_ at: Date, tag: String?) -> Reading {   // M's numbers as an idle session keeps them
        Reading(five: nil, week: Meter(pct: 37, resetsAt: mWeek), at: at, account: tag)
    }

    // the morning: T's 5-hour window reset overnight and the idle sessions' redraws lack it
    @Test func aFiveHourWindowThatResetIsNotAWeeklyOnlyAccount() {
        for tag in [nil, T] {
            var a = Accounts()
            _ = a.take(team(login + 76 * 60, five: Meter(pct: 26, resetsAt: tFive), tag: tag))   // 20:43
            let night = a.take(team(tFive + 30, five: nil, week: 30, tag: tag))                   // 00:10, a redraw
            #expect(night?.five == Meter(pct: 0, resetsAt: nil))
            let s = Logic.evaluate(main: night, now: tFive + 9 * hour)                               // 09:10
            #expect(s.daily == nil && s.five?.pct == 0 && s.week?.pct == 30)
            let before = Logic.evaluate(main: team(login + 76 * 60, five: Meter(pct: 26, resetsAt: tFive), tag: tag), now: login + 2 * hour)
            #expect(Visitors.plan(.standard, s) == Visitors.plan(.standard, before))           // no change of plan: the wife stays home
            let nine = a.take(team(morningFive - 2 * hour - 20 * 60, five: Meter(pct: 11, resetsAt: morningFive), week: 33, tag: tag))
            #expect(nine?.five == Meter(pct: 11, resetsAt: morningFive) && nine?.week?.pct == 33)
        }
    }

    // an account that never had a 5-hour window still shows none
    @Test func aWeeklyOnlyAccountGetsNoFiveHourWindow() {
        var a = Accounts()
        _ = a.take(max(login, tag: nil))
        #expect(a.take(max(login + hour, tag: nil))?.five == nil)
    }

    @Test func anUntaggedWeeklyOnlyReadingRecoversAfterAnAccountSwitch() {
        // Claude Code can omit both the five-hour window and the bridge account hash just
        // after an update. A stale old-account guard must not turn that valid weekly reading
        // into a permanent "don't know" state.
        var a = Accounts(week: mWeek, previous: tWeek, switchedAt: login, seen: login, reading: nil)
        let r = team(login + 60, five: nil, week: 73, tag: nil)
        let shown = a.take(r)
        #expect(shown?.five == nil)
        #expect(shown?.week == r.week)
    }

    @Test func theCurrentTaggedAccountWinsWhenAccountsShareAWeeklyReset() {
        // Two remembered accounts can have the same weekly reset. Once the bridge has
        // identified the current session's account, that identity is stronger evidence than
        // the coincident reset time.
        var a = Accounts(week: mWeek, previous: tWeek, switchedAt: login, seen: login, reading: nil,
                         id: T, weeks: [M: mWeek, T: tWeek], ids: [M, T])
        let r = max(login + 60, tag: T)
        #expect(a.take(r) == r)
    }

    @Test func aDuplicateWeeklyResetDoesNotReplaceAnExistingCurrentReading() {
        // Recovery is only for an account that has not produced a reading yet. Once the
        // current account is displayed, an idle session can still write a different account's
        // coincident weekly reset into the bridge and must not replace it.
        let current = team(login, five: Meter(pct: 26, resetsAt: tFive), tag: T)
        var a = Accounts(week: tWeek, previous: mWeek, switchedAt: login, seen: login, reading: current,
                         id: T, weeks: [M: mWeek, T: tWeek], ids: [M, T])
        #expect(a.take(max(login + 60, tag: T)) == current)
    }

    // PR #12's rule: with the bridge naming no account, 30 minutes of quiet lets an idle session of the
    // old account take the app back (overnight, any redraw of it). The named account ends that.
    @Test func anIdleOldSessionNeverTakesANamedAccountBack() {
        var unnamed = Accounts()
        _ = unnamed.take(max(login - hour, tag: nil))
        _ = unnamed.take(team(login + 60, five: Meter(pct: 26, resetsAt: tFive), tag: nil))
        #expect(unnamed.take(max(login + 3 * hour, tag: nil))?.week?.resetsAt == mWeek)      // the old guess: back to M

        var a = Accounts()
        _ = a.take(max(login - hour, tag: M))                                                   // signed in to M
        #expect(a.take(max(login + 30, tag: T)) == nil)                                        // /login: M's numbers, now named T
        #expect(a.switchedAt == login + 30 && a.letter == "B" && a.awaitingReading)
        let fresh = team(login + 76 * 60, five: Meter(pct: 26, resetsAt: tFive), tag: T)
        #expect(a.take(fresh) == fresh)
        #expect(!a.awaitingReading && a.take(max(login + 9 * hour, tag: T)) == fresh)           // 04:27, after hours of quiet
        #expect(a.switchedAt == login + 30 && a.id == T)
    }

    @Test func aLoginBackIsASwitchBack() {
        var a = Accounts()
        _ = a.take(max(login - hour, tag: M))
        _ = a.take(team(login + 60, five: Meter(pct: 26, resetsAt: tFive), tag: T))
        let back = login + 2 * hour
        #expect(a.take(team(back, five: Meter(pct: 30, resetsAt: tFive), tag: M)) == nil)   // T's numbers from an idle session
        #expect(a.switchedAt == back && a.letter == "A")
        #expect(a.take(max(back + 60, tag: M)) == max(back + 60, tag: M))
    }

    @Test func theFirstNamedReadingIsNotASwitch() {
        var a = Accounts()
        _ = a.take(team(login, five: nil, tag: nil))
        _ = a.take(team(login + 60, five: nil, tag: T))
        #expect(a.switchedAt == nil && a.letter == "A")
    }

    @Test func theNextWeekOfANamedAccountIsTheSameAccount() {
        var a = Accounts()
        _ = a.take(team(tWeek - hour, five: nil, tag: T))
        let next = Reading(five: nil, week: Meter(pct: 1, resetsAt: tWeek + Limits.weekLength), at: tWeek + hour, account: T)
        #expect(a.take(next) == next && a.switchedAt == nil)
    }

    // after the switch, T's 5-hour window reset and is empty: an old 5-hour hit is not T's
    @Test func anEmptyWindowAfterASwitchIgnoresTheOldAccountsHits() {
        let empty = Reading(five: Meter(pct: 0, resetsAt: nil), week: Meter(pct: 30, resetsAt: tWeek), at: tFive + hour)
        let retry = Limits.Hit(time: tFive + 30 * 60, week: false, resetsAt: tFive + 3 * hour)
        #expect(Limits.apply([retry], to: empty, lastAnswer: nil, now: tFive + 2 * hour, switchedAt: login) == empty)
        #expect(Limits.apply([retry], to: empty, lastAnswer: nil, now: tFive + 2 * hour)?.five?.pct == 100)   // no switch: its own
    }

    @Test func theNamesSurviveARestart() {
        let d = UserDefaults(suiteName: "TokenPetTests.accounts2")!
        d.removePersistentDomain(forName: "TokenPetTests.accounts2")
        var a = Accounts()
        _ = a.take(max(login - hour, tag: M))
        _ = a.take(team(login + 60, five: nil, tag: T))
        a.save(d)
        var b = Accounts.load(d)
        #expect(b == a && b.letter == "B")
        #expect(b.take(max(login + 120, tag: T)) == team(login + 60, five: nil, tag: T))
        d.removePersistentDomain(forName: "TokenPetTests.accounts2")
    }

    @Test func theBridgeNamesTheAccountByAHashOnly() {
        let ok = #"{"captured_at":1793751690,"account":"8EDCDE330cd0","rate_limits":{"seven_day":{"used_percentage":33,"resets_at":1793797200}}}"#
        #expect(Limits.bridge(Data(ok.utf8), fileDate: Date())?.account == "8edcde330cd0")
        for bad in [#""joshua@example.com""#, #""ab""#, "12"] {
            let j = #"{"account":\#(bad),"rate_limits":{"seven_day":{"used_percentage":33,"resets_at":1793797200}}}"#
            let r = Limits.bridge(Data(j.utf8), fileDate: Date())
            #expect(r != nil && r?.account == nil)
        }
    }

    @Test func theReadingLogRollsOver() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tokenpet-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("claude-readings.log")
        ReadingLog.append(String(repeating: "x", count: ReadingLog.limit + 1), to: url)
        ReadingLog.append("new", to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "new\n")
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("1").path))
        let line = ReadingLog.line(read: team(login, five: nil, tag: T), decision: "taken", shown: nil, accounts: Accounts())
        #expect(line.contains("account=\(T)") && line.contains("-> taken"))
    }
}
