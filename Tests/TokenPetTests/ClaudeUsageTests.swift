import Foundation
import Testing
@testable import TokenPet

// Claude's limits come from `claude -p /usage` per profile (LOGIC.md "Accounts"). The fixtures are the
// `usage_report` line Claude Code 2.1.332 prints with `--output-format stream-json --verbose`, ids and text cut.

private let askedAt = Date(timeIntervalSince1970: 1_795_682_000)   // 2026-11-26 08:33 UTC

/// One stream-json run: the init line, the assistant line with `usage_report`, and the result.
private func run(rateLimits: String, version: String = "2.1.332") -> Data {
    Data("""
    {"type":"system","subtype":"init","claude_code_version":"\(version)","apiKeySource":"none"}
    {"type":"assistant","message":{"model":"<synthetic>","content":[{"type":"text","text":"You are currently using your subscription to power your Claude Code usage"}]},"usage_report":{"session":{"total_cost_usd":0,"total_api_duration_ms":0,"total_duration_ms":4903,"total_lines_added":0,"total_lines_removed":0,"model_usage":{}},"rate_limits":\(rateLimits)}}
    {"type":"result","subtype":"success","is_error":false,"total_cost_usd":0}

    """.utf8)
}

/// 2.1.332, an account with a 5-hour and a weekly window plus a per-model weekly row.
private let both = """
{"limits":[{"kind":"session","group":"session","percent":93,"resets_at":"2026-11-26T11:00:00.31+00:00","scope":null,"severity":"warning","is_active":true},\
{"kind":"weekly_all","group":"weekly","percent":15,"resets_at":"2026-12-02T13:00:00.606596+00:00","scope":null,"severity":"normal","is_active":false},\
{"kind":"weekly_scoped","group":"weekly","percent":4,"resets_at":"2026-12-02T13:00:00.606744+00:00","scope":{"model":{"display_name":"Fable"},"surface":null},"severity":"normal","is_active":false}],\
"extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,"utilization":null,"currency":null}}
"""

/// 2.1.332, the requester's second account on 2026-11-26: no 5-hour window right now.
private let weekOnly = """
{"limits":[{"kind":"weekly_all","group":"weekly","percent":70,"resets_at":"2026-11-29T18:59:59.606596+00:00","scope":null,"severity":"normal","is_active":true}],\
"extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,"utilization":null,"currency":null}}
"""

private func limits(five: Double?, week: Double, weekReset: Date) -> ClaudeUsage.Answer {
    .limits(Reading(five: five.map { Meter(pct: $0, resetsAt: askedAt + 3600) }, week: Meter(pct: week, resetsAt: weekReset), at: askedAt))
}

@Suite struct ClaudeUsageParsing {
    @Test func readsTheRowsByKind() throws {
        guard case .limits(let r) = ClaudeUsage.parse(run(rateLimits: both), at: askedAt) else { Issue.record("no limits"); return }
        #expect(r.at == askedAt)
        #expect(r.five?.pct == 93 && abs((r.five?.resetsAt?.timeIntervalSince1970 ?? 0) - 1_795_690_800.31) < 0.01)
        #expect(r.week?.pct == 15 && abs((r.week?.resetsAt?.timeIntervalSince1970 ?? 0) - 1_796_216_400.6066) < 0.01)   // not the Fable row
    }

    @Test func aWeeklyOnlyAccountHasNoFiveHourMeter() {
        guard case .limits(let r) = ClaudeUsage.parse(run(rateLimits: weekOnly), at: askedAt) else { Issue.record("no limits"); return }
        #expect(r.five == nil && r.week?.pct == 70)
    }

    /// Claude Code drops `limits` when it answers from its cached snapshot (a 429, a held-back bearer) and sends
    /// `rate_limits: null` when there is nothing (API key, signed out): neither is a fresh answer.
    @Test func noFreshRowsIsNoLimits() {
        #expect(ClaudeUsage.parse(run(rateLimits: "null"), at: askedAt) == .noLimits)
        #expect(ClaudeUsage.parse(run(rateLimits: #"{"limits":null,"extra_usage":null}"#), at: askedAt) == .noLimits)
        #expect(ClaudeUsage.parse(run(rateLimits: #"{"limits":[{"kind":"weekly_scoped","group":"weekly","percent":4,"resets_at":null}]}"#), at: askedAt) == .noLimits)
    }

    /// Anything this parser does not know is "don't know", never a guess from the human text.
    @Test func unknownOutputIsUnreadable() {
        for bad in [Data(), Data("You are currently using your subscription\nCurrent session: 93% used".utf8),
                    run(rateLimits: #"{"extra_usage":null}"#),                                              // no limits key
                    run(rateLimits: #"{"limits":{"kind":"session"}}"#),                                     // not a list
                    run(rateLimits: #"{"limits":[{"kind":"session","percent":"93","resets_at":null}]}"#),     // percent not a number
                    run(rateLimits: #"{"limits":[{"kind":"session","percent":-1,"resets_at":null}]}"#),
                    run(rateLimits: #"{"limits":[{"kind":"session","percent":9,"resets_at":"Nov 26 at 8pm"}]}"#),
                    run(rateLimits: #"{"limits":[{"kind":"session","percent":9,"resets_at":1795734000}]}"#)] {
            #expect(ClaudeUsage.parse(bad, at: askedAt) == .unreadable)
        }
    }

    @Test func overAHundredIsFull() {
        let d = run(rateLimits: #"{"limits":[{"kind":"session","group":"session","percent":104,"resets_at":null}]}"#)
        guard case .limits(let r) = ClaudeUsage.parse(d, at: askedAt) else { Issue.record("no limits"); return }
        #expect(r.five?.pct == 100 && r.five?.resetsAt == nil)
    }

    @Test func theLoginNamesTheProfile() {
        #expect(ClaudeUsage.login(config: Data(#"{"oauthAccount":{"emailAddress":"a@example.com","displayName":"A"}}"#.utf8)) == "a@example.com")
        #expect(ClaudeUsage.login(config: Data(#"{"oauthAccount":null}"#.utf8)) == nil)
        #expect(ClaudeUsage.login(config: nil) == nil)
        let home = URL(fileURLWithPath: "/Users/x")
        #expect(ClaudeUsage.configURL(dir: nil, home: home).path == "/Users/x/.claude.json")
        #expect(ClaudeUsage.configURL(dir: "/Users/x/.claude-work", home: home).path == "/Users/x/.claude-work/.claude.json")
    }

    /// The command is the unmodified `/usage`: no session file, no user settings or hooks, no MCP servers.
    @Test func theCommand() {
        #expect(ClaudeUsage.arguments == ["-p", "/usage", "--no-session-persistence", "--setting-sources", "project",
                                          "--strict-mcp-config", "--output-format", "stream-json", "--verbose"])
    }
}

@Suite struct ClaudeAskCadence {
    @Test func atMostOncePerFiveMinutes() {
        var a = ClaudeAsk()
        #expect(a.allows(.start, backgroundOn: true, now: askedAt))
        a.record(limits(five: 10, week: 20, weekReset: askedAt + 86400), now: askedAt)
        for reason in [ClaudeAsk.Reason.start, .popover, .background] {
            #expect(!a.allows(reason, backgroundOn: true, now: askedAt + 299))
            #expect(a.allows(reason, backgroundOn: true, now: askedAt + 300))
        }
        #expect(a.allows(.popover, backgroundOn: true, now: askedAt - 3600))   // a clock set back does not lock it out
    }

    @Test func popoverOnlyMode() {
        let a = ClaudeAsk()
        #expect(!a.allows(.background, backgroundOn: false, now: askedAt))
        #expect(a.allows(.popover, backgroundOn: false, now: askedAt) && a.allows(.start, backgroundOn: false, now: askedAt))
    }

    @Test func backgroundEvery30MinutesGiveOrTake5() {
        #expect(ClaudeAsk.nextBackground(random: 0) == 25 * 60)
        #expect(ClaudeAsk.nextBackground(random: 0.5) == 30 * 60)
        #expect(ClaudeAsk.nextBackground(random: 1) == 35 * 60)
        #expect(ClaudeAsk.nextBackground(random: 7) == 35 * 60)
    }

    /// A refused ask (429/403 shows up as no fresh rows) holds the profile 1 h, then 2 h, 4 h … a day, and the
    /// background refresh stops asking it until the popover is opened; only a fresh answer clears it.
    @Test func backoffOnRefusal() {
        var accounts = ClaudeAccounts()
        let key = AccountKey.claudeDefault
        accounts.take(.noLimits, login: "a@example.com", for: key, now: askedAt)
        var a = accounts.ask(key)
        #expect(a.heldUntil == askedAt + 3600 && a.stopped)
        #expect(!a.allows(.popover, backgroundOn: true, now: askedAt + 3599) && !a.allows(.start, backgroundOn: true, now: askedAt + 3599))
        #expect(a.allows(.popover, backgroundOn: true, now: askedAt + 3600))
        #expect(!a.allows(.background, backgroundOn: true, now: askedAt + 3600))   // stopped until the popover opens
        accounts.popoverOpened()
        #expect(accounts.ask(key).allows(.background, backgroundOn: true, now: askedAt + 3600))

        var t = askedAt + 3600
        for hours in [2.0, 4, 8, 16, 24, 24] {
            accounts.take(.unreadable, login: "a@example.com", for: key, now: t)
            a = accounts.ask(key)
            #expect(a.heldUntil == t + hours * 3600)
            t = a.heldUntil!
        }
        accounts.take(limits(five: 1, week: 2, weekReset: t + 86400), login: "a@example.com", for: key, now: t)
        a = accounts.ask(key)
        #expect(a.backoff == 0 && a.heldUntil == nil && !a.stopped)
    }
}

@Suite struct ClaudeProfiles {
    let home = URL(fileURLWithPath: "/Users/x")

    /// The flaw of 0.3.8: two accounts whose weekly limits reset at the same moment shared one row. Each profile
    /// is asked on its own, so each row holds only its own numbers whatever their reset times.
    @Test func twoProfilesWithTheSameResetKeepTheirOwnNumbers() throws {
        var accounts = ClaudeAccounts()
        let added = accounts.add(dir: "/Users/x/.claude-work", home: home)
        let work = try #require(added)
        let reset = askedAt + 4 * 86400
        accounts.take(limits(five: 93, week: 15, weekReset: reset), login: "a@example.com", for: .claudeDefault, now: askedAt)
        accounts.take(limits(five: nil, week: 70, weekReset: reset), login: "b@example.com", for: work, now: askedAt + 1)
        #expect(accounts.selectedReading?.week?.pct == 15 && accounts.selectedReading?.five?.pct == 93)
        accounts.select(work)
        #expect(accounts.selectedReading?.week?.pct == 70 && accounts.selectedReading?.five == nil)
        let rows = accounts.rows(codex: nil)
        #expect(rows.map(\.login) == ["a@example.com", "b@example.com"])
        let codex = Reading(five: nil, week: Meter(pct: 3, resetsAt: nil), at: askedAt)
        #expect(accounts.rows(codex: codex).last?.key == .local && accounts.rows(codex: codex).count == 3)   // Codex: one local row
        #expect(rows.map { $0.reading?.week?.pct } == [15, 70])
        for _ in 0..<10 {   // answers arriving in any order never cross over
            accounts.take(limits(five: 94, week: 16, weekReset: reset), login: "a@example.com", for: .claudeDefault, now: askedAt + 600)
            accounts.take(limits(five: nil, week: 71, weekReset: reset), login: "b@example.com", for: work, now: askedAt + 600)
            #expect(accounts.selectedReading?.week?.pct == 71)
        }
    }

    /// `/login` to another account in the same profile: the next answer is the new account's, under its own
    /// name. If that ask gets no fresh rows, the old account's number is not shown under the new login.
    @Test func aLoginSwitchNeverShowsTheOldAccountsNumbers() {
        var accounts = ClaudeAccounts()
        accounts.take(limits(five: 100, week: 16, weekReset: askedAt + 6 * 86400), login: "a@example.com", for: .claudeDefault, now: askedAt)
        accounts.take(limits(five: nil, week: 67, weekReset: askedAt + 3 * 86400), login: "b@example.com", for: .claudeDefault, now: askedAt + 1800)
        #expect(accounts.selectedReading?.week?.pct == 67 && accounts.selectedReading?.five == nil)
        #expect(accounts.answer(.claudeDefault)?.login == "b@example.com")

        accounts.take(.noLimits, login: "a@example.com", for: .claudeDefault, now: askedAt + 3600)
        #expect(accounts.selectedReading == nil && accounts.answer(.claudeDefault)?.login == "a@example.com")
    }

    /// Between asks, and after a refused ask by the same login, the last number stays with its age.
    @Test func aRefusedAskKeepsTheLastNumberWithItsAge() {
        var accounts = ClaudeAccounts()
        accounts.take(limits(five: 40, week: 10, weekReset: askedAt + 86400), login: "a@example.com", for: .claudeDefault, now: askedAt)
        accounts.take(.noLimits, login: "a@example.com", for: .claudeDefault, now: askedAt + 1800)
        #expect(accounts.selectedReading?.five?.pct == 40 && accounts.answer(.claudeDefault)?.at == askedAt)
    }

    /// A parse failure is "don't know", not the previous number.
    @Test func aParseFailureShowsUnknown() {
        var accounts = ClaudeAccounts()
        accounts.take(limits(five: 40, week: 10, weekReset: askedAt + 86400), login: "a@example.com", for: .claudeDefault, now: askedAt)
        accounts.take(ClaudeUsage.parse(Data("Current session: 41% used".utf8), at: askedAt + 1800), login: "a@example.com",
                      for: .claudeDefault, now: askedAt + 1800)
        #expect(accounts.selectedReading == nil)
        #expect(eval(accounts.selectedReading, now: askedAt + 1800).known == false)
    }

    @Test func addingAndRemovingProfiles() throws {
        var accounts = ClaudeAccounts()
        #expect(accounts.add(dir: "/Users/x/.claude", home: home) == nil)          // that is the default profile
        #expect(accounts.add(dir: "", home: home) == nil)
        let added = accounts.add(dir: "/Users/x/.claude-work/", home: home)
        let work = try #require(added)
        #expect(work.dir == "/Users/x/.claude-work" && accounts.add(dir: "/Users/x/.claude-work", home: home) == nil)
        accounts.select(work)
        accounts.setNickname(" work ", for: work)
        #expect(accounts.nickname(for: work) == "work")
        accounts.remove(.claudeDefault)                                             // the default stays
        #expect(accounts.keys == [.claudeDefault, work])
        accounts.remove(work)
        #expect(accounts.keys == [.claudeDefault] && accounts.selected == .claudeDefault && accounts.nickname(for: work) == nil)
        accounts.take(.noLimits, login: nil, for: work, now: askedAt)               // a removed profile's late answer is dropped
        #expect(accounts.answer(work) == nil)
    }

    /// Rows saved by 0.3.8 and older were keyed by a guess (a weekly reset, an account hash): dropped on load.
    @Test func oldGuessedRowsAreDropped() throws {
        let d = try #require(UserDefaults(suiteName: "tokenpet-test-\(UUID().uuidString)"))
        d.set(Data(#"{"store":{"values":{},"nicknames":{"claude:week@9420":"ginko"}},"selected":{"value":"claude:week@9420"}}"#.utf8),
              forKey: "claude.readings")
        let loaded = ClaudeAccounts.load(d)
        #expect(loaded == ClaudeAccounts() && d.object(forKey: "claude.readings") == nil)
        var a = loaded
        a.take(limits(five: 1, week: 2, weekReset: askedAt + 86400), login: "a@example.com", for: .claudeDefault, now: askedAt)
        a.save(d)
        #expect(ClaudeAccounts.load(d) == a)
    }

    @Test func percentNeverRoundsUpToFull() {
        #expect(Fmt.pct(99.5) == "99%" && Fmt.pct(99.94) == "99%" && Fmt.pct(100) == "100%" && Fmt.pct(23.6) == "24%" && Fmt.pct(0) == "0%")
        var s = Snapshot(); s.known = true; s.five = Meter(pct: 99.6, resetsAt: nil)
        #expect(BarText.percent.text(s, cutscene: false, now: askedAt) == "99%" && !eval(Reading(five: s.five, week: nil, at: askedAt), now: askedAt).resting)
    }
}

/// Against the real Claude Code on this Mac, signed in: `TOKENPET_LIVE_CLAUDE=1 ./test.sh --filter LiveClaude`.
@Suite struct LiveClaude {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOKENPET_LIVE_CLAUDE"] == "1"))
    func theInstalledClaudeCodeAnswers() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cwd = FileManager.default.temporaryDirectory.appendingPathComponent("tokenpet-live-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: cwd) }
        let answer = ClaudeUsage.ask(dir: nil, home: home, cwd: cwd)
        guard case .limits(let r) = answer else { Issue.record("no fresh rows: \(answer)"); return }
        #expect(r.five != nil || r.week != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: cwd.path).isEmpty)   // nothing left in its folder
        print("live /usage:", ReadingLog.describe(r))
    }
}
