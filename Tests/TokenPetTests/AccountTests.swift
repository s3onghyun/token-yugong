import Foundation
import Testing
@testable import TokenPet

// Switching the Claude account (LOGIC.md "Another account"). Seen on this Mac on 2026-11-03: the old
// account hit its 5-hour limit, /login switched to an account with only a weekly window, and sessions
// started before the /login kept writing the old account into the same bridge file.

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
