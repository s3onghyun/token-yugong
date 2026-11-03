import Foundation
import Testing
@testable import TokenPet

// A used-up limit (LOGIC.md "Limit reached"). Claude Code's status line reports the last successful
// response, so it stops at 99%; the rejected request is in the session log, shaped like this.

private func logLine(_ type: String, resetsAt: Double, at ts: String = "2026-11-03T07:56:13.543Z") -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(#"""
    {"type":"assistant","timestamp":"\#(ts)","message":{"model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0},
     "content":[{"type":"text","text":"You've hit your session limit · resets 7:10pm (Asia/Seoul)"}]},
     "apiError":"usage_limit_reached","error":"rate_limit","isApiErrorMessage":true,"apiErrorStatus":429,
     "apiErrorParams":{"rate_limit_info":{"status":"rejected","resetsAt":\#(Int(resetsAt)),"rateLimitType":"\#(type)"}}}
    """#.utf8)) as! [String: Any]
}

@Suite struct LimitHit {
    let hitAt = Date(timeIntervalSince1970: 1_793_692_573.543)        // 2026-11-03 16:56 KST
    let fiveReset = Date(timeIntervalSince1970: 1_793_700_600)        // 19:10 KST
    var stale99: Reading { Reading(five: Meter(pct: 99, resetsAt: fiveReset), week: Meter(pct: 34, resetsAt: reset), at: hitAt - 120) }

    @Test func parsesTheLoggedRejection() {
        #expect(Limits.hit(logLine("five_hour", resetsAt: 1_793_700_600)) == Limits.Hit(time: hitAt, week: false, resetsAt: fiveReset))
        #expect(Limits.hit(logLine("seven_day", resetsAt: 1_794_164_400))?.week == true)
        #expect(Limits.hit(logLine("seven_day_opus", resetsAt: 1_794_164_400)) == nil)   // a per-model limit is not Grandpa's carrier
        var other = logLine("five_hour", resetsAt: 1_793_700_600); other["apiError"] = "overloaded"
        #expect(Limits.hit(other) == nil)
    }

    // the bug: the status line said 99% and Grandpa kept digging
    @Test func aStale99BecomesFullAndHeRests() throws {
        let now = hitAt + 600
        #expect(eval(stale99, now: now).state != .resting)              // before: stuck at 99
        let r = try #require(Limits.apply([Limits.Hit(time: hitAt, week: false, resetsAt: fiveReset)], to: stale99, lastAnswer: hitAt - 120, now: now))
        let s = eval(r, now: now)
        #expect(s.five == Meter(pct: 100, resetsAt: fiveReset) && s.resting && s.wakeAt == fiveReset && s.state == .resting)
        #expect(BarText.percent.text(s, cutscene: false, now: now) == "2h 3m")      // the countdown to 19:10
        #expect(r.at == hitAt)                                          // "as of" the rejection
    }

    // seen on this Mac: after the rejection the status line dropped five_hour, leaving a 34% "weekly-only" reading
    @Test func aMissingWindowIsFilledByTheHit() throws {
        let weekOnly = Reading(five: nil, week: Meter(pct: 34, resetsAt: reset), at: hitAt + 180)
        let r = try #require(Limits.apply([Limits.Hit(time: hitAt, week: false, resetsAt: fiveReset)], to: weekOnly, lastAnswer: nil, now: hitAt + 300))
        let s = eval(r, now: hitAt + 300)
        #expect(s.resting && s.daily == nil && s.headline?.pct == 100)
    }

    @Test func noStatusLineStillRests() throws {
        let r = try #require(Limits.apply([Limits.Hit(time: hitAt, week: true, resetsAt: reset)], to: nil, lastAnswer: nil, now: hitAt + 60))
        let s = eval(r, now: hitAt + 60)
        #expect(s.known && s.resting && s.wakeAt == reset && s.week?.pct == 100)
    }

    @Test func anAnswerAfterTheHitEndsIt() {
        // another account, or extra usage: Claude answered again, so the limit is not in the way
        let r = Limits.apply([Limits.Hit(time: hitAt, week: false, resetsAt: fiveReset)], to: stale99, lastAnswer: hitAt + 30, now: hitAt + 60)
        #expect(r == stale99)
    }

    @Test func aLaterWindowWins() {
        let fresh = Reading(five: Meter(pct: 3, resetsAt: fiveReset + 5 * hour), week: nil, at: fiveReset + 60)
        let r = Limits.apply([Limits.Hit(time: hitAt, week: false, resetsAt: fiveReset)], to: fresh, lastAnswer: nil, now: fiveReset + 120)
        #expect(r == fresh)
    }

    // the reset: morning for a few minutes, then the hit is over
    @Test func theResetWakesHimThenTheHitIsForgotten() throws {
        let hit = [Limits.Hit(time: hitAt, week: false, resetsAt: fiveReset)]
        let r = try #require(Limits.apply(hit, to: stale99, lastAnswer: nil, now: fiveReset + 60))
        let s = eval(r, now: fiveReset + 60)
        #expect(!s.resting && s.state == .morning && s.five == Meter(pct: 0, resetsAt: nil))
        #expect(Limits.apply(hit, to: nil, lastAnswer: nil, now: fiveReset + Logic.morningFor + 1) == nil)
    }

    @Test func percentNeverRoundsUpToFull() {
        #expect(Fmt.pct(99.5) == "99%" && Fmt.pct(99.94) == "99%" && Fmt.pct(100) == "100%" && Fmt.pct(23.6) == "24%" && Fmt.pct(0) == "0%")
        var s = Snapshot(); s.known = true; s.five = Meter(pct: 99.6, resetsAt: nil)
        #expect(BarText.percent.text(s, cutscene: false, now: hitAt) == "99%" && !eval(Reading(five: s.five, week: nil, at: hitAt), now: hitAt).resting)
    }
}
