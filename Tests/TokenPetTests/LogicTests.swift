import Foundation
import Testing
import TokenPetAssets
@testable import TokenPet

// One test per row of LOGIC.md, then the edge cases. Times are absolute; the weekly window is the
// one measured on this Mac: resets Mon 2026-11-09 04:00 KST (= Sun 19:00 UTC).

let reset = Date(timeIntervalSince1970: 1_794_164_400)
let weekStart = reset.addingTimeInterval(-7 * 86400)          // Mon 2026-11-02 04:00 KST
let hour: TimeInterval = 3600, day: TimeInterval = 86400
let share = 100.0 / 7

func claude(five: Meter? = nil, week: Meter? = nil, at: Date = weekStart) -> Reading { Reading(five: five, week: week, at: at) }
/// Grandpa watches `r`; `codex` (if given) goes to the grandson, as in the standard family.
func eval(_ r: Reading?, now: Date, codex: Reading? = nil) -> Snapshot {
    Logic.evaluate(main: r, members: codex.map { [Role.grandson: Optional($0)] } ?? [:], now: now)
}
func json(_ s: String) -> Data { Data(s.utf8) }

// MARK: - Reading the inputs

@Suite struct Parsing {
    let fileDate = Date(timeIntervalSince1970: 1_000)

    @Test func bridgeBothWindows() throws {
        let r = try #require(Limits.bridge(json(#"{"captured_at":1793615035,"rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1793620000},"seven_day":{"used_percentage":19,"resets_at":1794164400}}}"#), fileDate: fileDate))
        #expect(r.five == Meter(pct: 42.5, resetsAt: Date(timeIntervalSince1970: 1_793_620_000)))
        #expect(r.week == Meter(pct: 19, resetsAt: reset))
        #expect(r.at == Date(timeIntervalSince1970: 1_793_615_035))
    }

    @Test func bridgeWeeklyOnly() throws {
        let r = try #require(Limits.bridge(json(#"{"captured_at":1793615035,"rate_limits":{"seven_day":{"used_percentage":19,"resets_at":1794164400}}}"#), fileDate: fileDate))
        #expect(r.five == nil)
        #expect(r.week?.pct == 19)
    }

    @Test func maxPlanHistorySupplementsTheMissingFiveHourWindow() throws {
        // Redacted shape captured on this Mac for a Claude Max x20 account.  `fh` is compact,
        // timestamped in milliseconds, and has no reset time; the status line supplies the week.
        let history = try #require(Limits.planUsageHistory(json(#"{"version":1,"samples":[{"t":1794000000000,"org":"<redacted>","u":{"fh":34,"sd":59}}]}"#)))
        #expect(history.five == Meter(pct: 34, resetsAt: nil, resetUnavailable: true))
        let bridge = try #require(Limits.bridge(json(#"{"captured_at":1794000005,"rate_limits":{"seven_day":{"used_percentage":59,"resets_at":1794164400}}}"#), fileDate: fileDate))
        let r = try #require(Limits.supplement(bridge, with: history, now: Date(timeIntervalSince1970: 1_794_000_010)))
        #expect(r.five == Meter(pct: 34, resetsAt: nil, resetUnavailable: true))
        #expect(r.week == Meter(pct: 59, resetsAt: reset))
        #expect(r.account == nil && r.at == bridge.at)       // status line remains the account authority
    }

    @Test func absentOrStaleMaxHistoryKeepsTheClearWeeklyFallback() throws {
        let bridge = try #require(Limits.bridge(json(#"{"captured_at":1794000005,"rate_limits":{"seven_day":{"used_percentage":59,"resets_at":1794164400}}}"#), fileDate: fileDate))
        let absent = Limits.planUsageHistory(json(#"{"version":1,"samples":[{"t":1794000000000,"u":{"fh":null,"sd":59}}]}"#))
        #expect(absent == nil)
        #expect(Limits.supplement(bridge, with: absent, now: Date(timeIntervalSince1970: 1_794_000_010))?.five == nil)
        let stale = try #require(Limits.planUsageHistory(json(#"{"samples":[{"t":1793000000000,"u":{"fh":34}}]}"#)))
        #expect(Limits.supplement(bridge, with: stale, now: Date(timeIntervalSince1970: 1_794_000_010))?.five == nil)
    }

    @Test func savedMetersFromBeforeTheHistoryFallbackStillDecode() throws {
        let old = try JSONDecoder().decode(Meter.self, from: json(#"{"pct":34,"resetsAt":null}"#))
        #expect(old == Meter(pct: 34, resetsAt: nil))
    }

    @Test(arguments: [
        "",                                                     // empty file
        "not json",                                             // corrupt
        #"{"captured_at":1793615035,"rate_limits":{"seven_da"#, // cut off mid-write
        #"{"captured_at":1793615035}"#,                         // no rate_limits
        #"{"rate_limits":{}}"#,                                 // no window at all
        #"{"rate_limits":null}"#,
        #"[1,2,3]"#,
        #"{"rate_limits":{"seven_day":{"used_percentage":"19","resets_at":1794164400}}}"#,  // number as text
        #"{"rate_limits":{"seven_day":{"used_percentage":-5,"resets_at":1794164400}}}"#,    // impossible value
        #"{"rate_limits":{"seven_day":{"resets_at":1794164400}}}"#,                         // percent missing
    ])
    func bridgeNothingUsable(_ text: String) {
        #expect(Limits.bridge(json(text), fileDate: fileDate) == nil)
    }

    @Test func bridgeClampsAndFallsBack() throws {
        let r = try #require(Limits.bridge(json(#"{"rate_limits":{"seven_day":{"used_percentage":130}}}"#), fileDate: fileDate))
        #expect(r.week == Meter(pct: 100, resetsAt: nil))   // over 100 is shown as 100; no reset time = unknown
        #expect(r.at == fileDate)                            // no captured_at: the file's own time, never "now"
    }

    @Test func codexWeeklyOnly() throws {
        let line = #"{"timestamp":"2026-11-02T10:04:02.404Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"output_tokens":90}},"rate_limits":{"primary":{"used_percent":38.0,"window_minutes":10080,"resets_at":1793774134},"secondary":null}}}"#
        let r = try #require(Limits.codex(json(line)))
        #expect(r.five == nil)
        #expect(r.week == Meter(pct: 38, resetsAt: Date(timeIntervalSince1970: 1_793_774_134)))
        #expect(CodexReader.output(json(line))?.tokens == 90)
    }

    @Test func codexBothAndUnknownWindows() throws {
        let both = #"{"timestamp":"2026-11-02T10:04:02.404Z","payload":{"rate_limits":{"primary":{"used_percent":12,"window_minutes":300,"resets_at":1793620000},"secondary":{"used_percent":40,"window_minutes":10080,"resets_at":1793774134}}}}"#
        let r = try #require(Limits.codex(json(both)))
        #expect(r.five?.pct == 12 && r.week?.pct == 40)
        let odd = #"{"timestamp":"2026-11-02T10:04:02.404Z","payload":{"rate_limits":{"primary":{"used_percent":12,"window_minutes":60,"resets_at":1793620000}}}}"#
        #expect(Limits.codex(json(odd)) == nil)                                   // unknown window length: not guessed
        #expect(Limits.codex(json(String(both.prefix(80)))) == nil)               // partial line
        #expect(Limits.codex(json(#"{"payload":{"rate_limits":{"primary":{"used_percent":12,"window_minutes":300}}}}"#)) == nil)  // no timestamp
    }
}

// MARK: - LOGIC.md rules

@Suite struct Rules {
    // Rule 1: no data -> "don't know"
    @Test func noDataMeansDontKnow() {
        let s = eval(nil, now: weekStart + day)
        #expect(!s.known && !s.resting && s.five == nil && s.week == nil && s.daily == nil && s.projected == nil)
        #expect(s.carrier == 0)
    }

    // Rule 2: a window whose reset has passed is a new, empty window with an unknown next reset
    @Test func resetInThePast() {
        let r = claude(five: Meter(pct: 100, resetsAt: weekStart + 2 * hour), week: Meter(pct: 30, resetsAt: reset))
        let s = eval(r, now: weekStart + 2 * hour + 60)
        #expect(s.five == Meter(pct: 0, resetsAt: nil))
        #expect(!s.resting)                                    // 100% before the reset no longer counts
        #expect(s.state == .morning)                           // and it reset a minute ago
        let later = eval(r, now: weekStart + 3 * hour)
        #expect(later.state != .morning && later.five?.pct == 0)
    }

    @Test func resetExactlyNowCountsAsPassed() {
        let s = eval(claude(five: Meter(pct: 70, resetsAt: weekStart + hour), week: Meter(pct: 10, resetsAt: reset)), now: weekStart + hour)
        #expect(s.five == Meter(pct: 0, resetsAt: nil) && s.justReset == weekStart + hour)
    }

    // Rule 3: a full window -> resting until it resets
    @Test func fullWindowRests() {
        let fiveReset = weekStart + 3 * hour
        let s = eval(claude(five: Meter(pct: 100, resetsAt: fiveReset), week: Meter(pct: 40, resetsAt: reset)), now: weekStart + hour)
        #expect(s.resting && s.wakeAt == fiveReset && s.state == .resting)
    }

    @Test func bothFullWaitsForTheLater() {
        let s = eval(claude(five: Meter(pct: 100, resetsAt: weekStart + 3 * hour), week: Meter(pct: 100, resetsAt: reset)), now: weekStart + hour)
        #expect(s.wakeAt == reset)
    }

    @Test func fullWithoutResetTimeSaysUnknownWake() {
        let s = eval(claude(week: Meter(pct: 100, resetsAt: nil)), now: weekStart + hour)
        #expect(s.resting && s.wakeAt == nil)                  // shown as "?", never an invented time
    }

    @Test func justUnderFullDoesNotRest() {
        let s = eval(claude(five: Meter(pct: 99.9, resetsAt: weekStart + 4 * hour + 59 * 60), week: Meter(pct: 10, resetsAt: reset)),
                     now: weekStart + 4 * hour + 58 * 60)
        #expect(!s.resting && s.state == .straining)
    }

    // Rule 4: weekly-only accounts carry the week; today's share only sets the pace
    @Test func noFiveHourWindowUsesDailyShare() {
        // measured on this Mac: day 0 (Mon 19:24 KST), 19% of the week used
        let now = Date(timeIntervalSince1970: 1_793_615_035)
        let s = eval(claude(week: Meter(pct: 19, resetsAt: reset), at: now), now: now)
        #expect(s.five == nil)
        let d = try! #require(s.daily)
        #expect(d.dayStart == weekStart && d.dayEnd == weekStart + day)
        #expect(abs(d.fill - 19 / share) < 1e-9)               // 133% of today's share
        #expect(!s.resting && s.wakeAt == nil && s.state == .straining)   // ahead of pace: sweating, never a forced nap
        #expect(s.carrier == 0.19)                             // the carrier is the week
    }

    @Test func requesterDayOneIsNotARest() {
        // reported 2026-11-03: Tue 01:08 KST, still day 0 of the week that began Mon 04:00, 21% used
        let now = weekStart + 21 * hour + 8 * 60
        let s = eval(claude(week: Meter(pct: 21, resetsAt: reset), at: now), now: now)
        #expect(!s.resting && s.state == .straining && s.carrier == 0.21 && s.week?.resetsAt == reset)
    }

    @Test func weeklyOnlyRestsOnlyAtTheWeeklyLimit() {
        let now = weekStart + 3 * day + hour
        let full = eval(claude(week: Meter(pct: 100, resetsAt: reset)), now: now)
        #expect(full.resting && full.wakeAt == reset && full.state == .resting && full.carrier == 1)
        let nearly = eval(claude(week: Meter(pct: 99.9, resetsAt: reset)), now: now)
        #expect(!nearly.resting && nearly.state == .straining)
    }

    @Test func unusedDaysCarryOver() {
        let s = eval(claude(week: Meter(pct: 19, resetsAt: reset)), now: weekStart + day + hour)   // day 1
        #expect(abs(s.daily!.fill - (19 - share) / share) < 1e-9)    // 33%
        #expect(!s.resting && s.state == .lively)
        let s3 = eval(claude(week: Meter(pct: 19, resetsAt: reset)), now: weekStart + 3 * day + hour)
        #expect(s3.daily!.fill == 0)                                   // under pace: never negative
        let late = eval(claude(week: Meter(pct: 86, resetsAt: reset)), now: reset - 2 * hour)   // day 6, behind pace
        #expect(late.state == .lively)                                 // a high weekly % alone does not strain him
    }

    @Test func dailyShareExactlyAtThreshold() {
        let now = weekStart + 2 * day + 5 * hour                       // day 2: fair use so far = 3/7
        let at = eval(claude(week: Meter(pct: 3 * share, resetsAt: reset)), now: now)
        #expect(abs(at.daily!.fill - 1) < 1e-9 && !at.resting && at.state == .straining)
        let under = eval(claude(week: Meter(pct: 3 * share - 0.01, resetsAt: reset)), now: now)
        #expect(under.daily!.fill < 1 && under.state == .steady)
        let steady = eval(claude(week: Meter(pct: 2.75 * share + 1e-9, resetsAt: reset)), now: now)   // 0.75 of today's share (+ float slack)
        #expect(steady.state == .steady)
        let lively = eval(claude(week: Meter(pct: 2.75 * share - 0.01, resetsAt: reset)), now: now)
        #expect(lively.state == .lively)
    }

    @Test func dailyDayBoundariesAndClamp() {
        let last = eval(claude(week: Meter(pct: 50, resetsAt: reset)), now: reset - 60)
        #expect(last.daily!.dayStart == weekStart + 6 * day && last.daily!.dayEnd == reset)
        // a reset more than a week away (odd data): day 0, never a negative day
        let early = eval(claude(week: Meter(pct: 5, resetsAt: reset)), now: weekStart - hour)
        #expect(early.daily!.dayStart == weekStart)
    }

    @Test func weekRolledOverHasNoDailyUntilTheNextReading() {
        let s = eval(claude(week: Meter(pct: 90, resetsAt: reset)), now: reset + hour)
        #expect(s.daily == nil && s.week == Meter(pct: 0, resetsAt: nil) && !s.resting)
    }

    @Test func fiveHourPresentMeansNoDaily() {
        let s = eval(claude(five: Meter(pct: 10, resetsAt: weekStart + 4 * hour), week: Meter(pct: 30, resetsAt: reset)), now: weekStart + 3 * hour)
        #expect(s.daily == nil && s.carrier == 0.10)
    }

    // Rule 5: morning for 5 minutes after any reset or new day
    @Test func newDayMorning() {
        let s = eval(claude(week: Meter(pct: 15, resetsAt: reset)), now: weekStart + day + 60)
        #expect(s.state == .morning)
        let edge = eval(claude(week: Meter(pct: 15, resetsAt: reset)), now: weekStart + day + 300)
        #expect(edge.state != .morning)                                // exactly 5 minutes: over
    }

    @Test func restingBeatsMorning() {
        let s = eval(claude(week: Meter(pct: 100, resetsAt: reset)), now: weekStart + day + 60)  // a new day, but the week is used up
        #expect(s.justReset != nil && s.state == .resting)
    }

    // Rule 6: working pace, exactly at each threshold (five-hour window half gone: pace = 2 x used)
    @Test(arguments: [(30.0, PetState.lively), (37.4, .lively), (37.5, .steady), (54.9, .steady), (55, .straining)])
    func paceThresholds(_ pct: Double, _ want: PetState) {
        let now = weekStart + 10 * hour
        let s = eval(claude(five: Meter(pct: pct, resetsAt: now + 2.5 * hour), week: Meter(pct: 1, resetsAt: reset)), now: now)
        #expect(s.state == want)
    }

    @Test func eightyPercentStrainsWhateverThePace() {
        let now = weekStart + 10 * hour
        let at = eval(claude(five: Meter(pct: 80, resetsAt: now + 1)), now: now)          // window nearly over: pace 80
        #expect(at.state == .straining)
        let under = eval(claude(five: Meter(pct: 79.9, resetsAt: now + 1)), now: now)
        #expect(under.state == .steady)
    }

    @Test func freshWindowIsNotJudgedOnMinutes() {
        let now = weekStart + 10 * hour
        let s = eval(claude(five: Meter(pct: 5, resetsAt: now + 5 * hour - 60)), now: now)  // 1 minute in
        #expect(abs(s.projected! - 5 / 0.12) < 1e-9 && s.state == .lively)
    }

    @Test func bothWindowsTheHotterOneWins() {
        let now = weekStart + 3.5 * day                                // week half gone
        let s = eval(claude(five: Meter(pct: 30, resetsAt: now + 2.5 * hour), week: Meter(pct: 70, resetsAt: reset)), now: now)
        #expect(abs(s.projected! - 140) < 1e-9 && s.state == .straining)   // weekly 70% at half time
    }
}

// MARK: - Edge cases

@Suite struct Edges {
    @Test func staleReadingIsShownAsOfItsTime() {
        let captured = weekStart + 5 * hour
        let s = eval(claude(week: Meter(pct: 10, resetsAt: reset), at: captured), now: weekStart + 2 * day + 5 * hour)
        #expect(s.known && s.captured == captured && s.week?.pct == 10)     // a lower bound; the popover prints the time
    }

    @Test func clockMovedBackBeforeTheCapture() {
        let s = eval(claude(week: Meter(pct: 10, resetsAt: reset), at: weekStart + 5 * hour), now: weekStart + 4 * hour)
        #expect(s.known && s.week?.pct == 10 && s.daily != nil)
    }

    @Test func sameAnswerInSeoulAndUTC() {
        let r = claude(five: Meter(pct: 20, resetsAt: weekStart + 30 * hour), week: Meter(pct: 19, resetsAt: reset))
        let rw = claude(week: Meter(pct: 19, resetsAt: reset))
        let now = weekStart + 28 * hour
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        var out: [String] = []
        for tz in ["Asia/Seoul", "UTC", "America/Los_Angeles"] {
            NSTimeZone.default = TimeZone(identifier: tz)!
            let a = eval(r, now: now), b = eval(rw, now: now)
            out.append("\(a.state) \(a.projected!) \(b.daily!) \(b.state)")
        }
        #expect(Set(out).count == 1)
    }

    @Test func clockTextFollowsTheTimeZone() {   // the language is passed in: tests run in parallel, so none flips L.lang
        let now = reset - 2 * day
        #expect(Fmt.clock(reset, now: now, tz: TimeZone(identifier: "Asia/Seoul")!, lang: .en) == "Mon 04:00")
        #expect(Fmt.clock(reset, now: now, tz: TimeZone(identifier: "UTC")!, lang: .en) == "Sun 19:00")
        #expect(Fmt.clock(reset, now: reset - hour, tz: TimeZone(identifier: "Asia/Seoul")!, lang: .en) == "04:00")  // same day: time only
        #expect(Fmt.clock(reset, now: now, tz: TimeZone(identifier: "Asia/Seoul")!, lang: .ko) == "월 04:00")
    }

    @Test func codexLogsOlderThanTheWindow() {
        let old = Reading(five: nil, week: Meter(pct: 38, resetsAt: weekStart + hour), at: weekStart - 2 * day)
        let s = eval(nil, now: weekStart + 2 * hour, codex: old)
        #expect(s.members[.grandson]?.reading?.week == Meter(pct: 0, resetsAt: nil) && s.members[.grandson]?.fill == 0)
        #expect(!s.known)                                    // Codex never stands in for Claude
    }

    @Test func codexBasket() {
        let now = weekStart + 2 * hour
        let weekly = Reading(five: nil, week: Meter(pct: 66, resetsAt: weekStart + 2.5 * day), at: now)
        #expect(eval(nil, now: now, codex: weekly).members[.grandson]?.fill == 0.66)   // weekly-only: the basket is the week
        let five = Reading(five: Meter(pct: 25, resetsAt: now + hour), week: Meter(pct: 90, resetsAt: reset), at: now)
        #expect(eval(nil, now: now, codex: five).members[.grandson]?.fill == 0.25)
        #expect(eval(nil, now: now).members[.grandson] == nil)        // nobody watches Codex: no grandson
    }
}

// MARK: - Live pace

@Suite struct PaceTests {
    let now = weekStart + 10 * hour

    @Test func rateCountsTheLastThreeMinutes() {
        let ev: [(time: Date, tokens: Int)] = [(now - 180, 999), (now - 179, 300), (now - 60, 300), (now, 300), (now + 5, 999)]
        #expect(Pace.rate(ev, now: now) == 300)               // 900 tokens / 3 min; the edge and the future excluded
        #expect(Pace.rate([], now: now) == 0)
    }

    @Test(arguments: [(0.0, Pace.Level.idle), (49.9, .idle), (50, .low), (1999, .low), (2000, .high), (7999, .high), (8000, .veryHigh)])
    func levelsExactlyAtBounds(_ rate: Double, _ want: Pace.Level) {
        var p = Pace(); p.update(rate: rate, now: now)
        #expect(p.level == want)
    }

    @Test func dropsOnlyWellBelowTheBound() {
        var p = Pace(); p.update(rate: 2500, now: now)
        #expect(p.level == .high)
        p = Pace(); p.update(rate: 2000, now: now); p.update(rate: 1600, now: now + 1e6)
        #expect(p.level == .high)                             // 1600 = 0.8 x 2000: still high
        p.update(rate: 1599, now: now + 2e6)
        #expect(p.level == .low)
    }

    @Test func smoothing() {
        var p = Pace(); p.update(rate: 0, now: now); p.update(rate: 6000, now: now + 60)
        #expect(abs(p.smoothed - 6000 * (1 - exp(-1))) < 1e-6)  // one time constant: 63%
    }

    @Test func noFlickerAroundABound() {
        var p = Pace(), changes = 0, last = Pace.Level.idle
        p.update(rate: 2100, now: now); last = p.level
        for i in 1...90 {                                      // 30 minutes of a rate bouncing 1700 <-> 2300 every 20 s
            p.update(rate: i % 2 == 0 ? 2300 : 1700, now: now + Double(i) * 20)
            if p.level != last { changes += 1; last = p.level }
        }
        #expect(changes == 0)
    }

    @Test func clockMovedBackIsNotTime() {
        var p = Pace(); p.update(rate: 1000, now: now); p.update(rate: 9000, now: now - hour)
        #expect(p.smoothed == 1000)
    }

    @Test func tempoAndSpeed() {
        #expect(Pace.speed[.low]! < Pace.speed[.high]! && Pace.speed[.high]! < Pace.speed[.veryHigh]!)
        var p = Pace(); p.update(rate: 0, now: now); #expect(p.tempo == .idle)
        p = Pace(); p.update(rate: 9000, now: now); #expect(p.tempo == .sweating)
        p = Pace(); p.update(rate: 300, now: now); #expect(p.tempo == .working)
        #expect(Pace.ease(1, to: 1.5, dt: 0) == 1)
        #expect(abs(Pace.ease(1, to: 1.5, dt: 60) - 1.5) < 1e-9)
        #expect(Pace.ease(1, to: 1.5, dt: -5) == 1)
    }

    @Test func idleLeansAndSweatingSweats() {
        let t = 0.1
        #expect(TokenPetAssets.signature(.lively, t: t, night: false, tempo: .idle)
                != TokenPetAssets.signature(.lively, t: t, night: false, tempo: .working))
        #expect(TokenPetAssets.signature(.lively, t: t, night: false, tempo: .sweating).contains(" true "))
        // resting and morning ignore the tempo: a tired Grandpa does not dig faster
        for st in [PetState.resting, .morning] {
            #expect(TokenPetAssets.signature(st, t: t, night: false, tempo: .sweating)
                    == TokenPetAssets.signature(st, t: t, night: false, tempo: .idle))
        }
    }
}

// MARK: - Local log readers

@Suite struct Readers {
    func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("tokenpet-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @Test func claudeLogsSkipJunkAndDuplicates() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let ts = Limits.iso.string(from: Date().addingTimeInterval(-60))
        let line = #"{"type":"assistant","timestamp":"\#(ts)","requestId":"r1","message":{"id":"m1","usage":{"input_tokens":10,"output_tokens":200,"cache_creation_input_tokens":5}}}"#
        let err = #"{"type":"assistant","isApiErrorMessage":true,"timestamp":"\#(ts)","message":{"id":"m2","usage":{"output_tokens":7}}}"#
        let text = [line, line, "garbage {\"type\":\"assistant\",\"usage\":{", err, #"{"type":"user"}"#].joined(separator: "\n")
            + "\n" + String(line.prefix(60))                     // a partial last line, still being written
        try text.write(to: dir.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        let sc = LogScanner(root: dir); sc.scan()
        #expect(sc.events.count == 1)
        #expect(sc.events.first?.output == 200 && sc.events.first?.tokens == 215)
        // the partial line is read once it is complete
        let h = try FileHandle(forWritingTo: dir.appendingPathComponent("a.jsonl"))
        try h.seekToEnd(); try h.write(contentsOf: Data(line.dropFirst(60).replacingOccurrences(of: "m1", with: "m3").utf8 + [0x0A])); try h.close()
        sc.scan()
        #expect(sc.events.count == 2 && sc.events.last?.output == 200)   // the completed line (message m3) counted once
    }

    @Test func codexReaderTakesTheNewestLine() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let t1 = Limits.iso.string(from: Date().addingTimeInterval(-120)), t2 = Limits.iso.string(from: Date().addingTimeInterval(-30))
        func l(_ t: String, _ pct: Int, _ out: Int) -> String {
            #"{"timestamp":"\#(t)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"output_tokens":\#(out)}},"rate_limits":{"primary":{"used_percent":\#(pct),"window_minutes":10080,"resets_at":\#(Int(Date().timeIntervalSince1970) + 86400)}}}}"#
        }
        try [l(t1, 10, 100), "{broken", l(t2, 12, 50)].joined(separator: "\n").write(to: dir.appendingPathComponent("rollout-a.jsonl"), atomically: true, encoding: .utf8)
        let r = CodexReader(root: dir); r.scan()
        #expect(r.reading?.week?.pct == 12)
        #expect(r.events.map(\.tokens).reduce(0, +) == 150)
    }

    @Test func bridgeScriptKeepsOnlyRateLimits() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../bridge/statusline-bridge.sh").standardized
        func run(_ input: String) throws -> String {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = [script.path]
            p.environment = ["TOKENPET_DIR": dir.path, "PATH": "/usr/bin:/bin:/opt/homebrew/bin"]
            let i = Pipe(), o = Pipe(); p.standardInput = i; p.standardOutput = o
            try p.run(); i.fileHandleForWriting.write(Data(input.utf8)); try i.fileHandleForWriting.close(); p.waitUntilExit()
            return String(decoding: o.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }
        let line = try run(#"{"session_id":"secret","cwd":"/x","rate_limits":{"seven_day":{"used_percentage":19,"resets_at":1794164400}}}"#)
        #expect(line == "🐾 week 19%")
        let saved = try String(contentsOf: dir.appendingPathComponent("limits.json"), encoding: .utf8)
        #expect(!saved.contains("secret") && !saved.contains("cwd"))
        #expect(Limits.bridge(Data(saved.utf8), fileDate: Date())?.week?.pct == 19)
        _ = try run(#"{"session_id":"s"}"#)                     // before the first response: no rate_limits
        #expect(try String(contentsOf: dir.appendingPathComponent("limits.json"), encoding: .utf8) == saved)   // kept, not wiped
    }

    @Test func bridgePinsAStatusLineSessionToItsFirstAccount() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../bridge/statusline-bridge.sh").standardized
        func run(_ input: String, accountID: String) throws -> Reading {
            try #"{"oauthAccount":{"accountUuid":"\#(accountID)"}}"#.write(to: config.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = [script.path]
            p.environment = ["TOKENPET_DIR": dir.path, "CLAUDE_CONFIG_DIR": config.path, "PATH": "/usr/bin:/bin:/opt/homebrew/bin"]
            let i = Pipe(); p.standardInput = i
            try p.run(); i.fileHandleForWriting.write(Data(input.utf8)); try i.fileHandleForWriting.close(); p.waitUntilExit()
            return try #require(Limits.bridge(Data(contentsOf: dir.appendingPathComponent("limits.json")), fileDate: Date()))
        }
        let oldID = "old-account-id", newID = "new-account-id"
        let old = try run(#"{"session_id":"old-session","rate_limits":{"seven_day":{"used_percentage":37,"resets_at":1794164400}}}"#, accountID: oldID)
        // `/login` changes the global config. An old session redraw must retain its first account hash.
        let oldRedraw = try run(#"{"session_id":"old-session","rate_limits":{"seven_day":{"used_percentage":38,"resets_at":1794164400}}}"#, accountID: newID)
        let fresh = try run(#"{"session_id":"new-session","rate_limits":{"seven_day":{"used_percentage":57,"resets_at":1794164400}}}"#, accountID: newID)
        #expect(old.account != nil && oldRedraw.account == old.account && fresh.account != old.account)
        let stored = try FileManager.default.contentsOfDirectory(at: dir.appendingPathComponent("sessions"), includingPropertiesForKeys: nil)
        #expect(stored.count == 2)
        for u in stored {
            let text = try String(contentsOf: u, encoding: .utf8)
            #expect(!u.lastPathComponent.contains("session") && !text.contains(oldID) && !text.contains(newID))
        }
    }
}
