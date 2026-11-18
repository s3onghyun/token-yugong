import Foundation
import Testing
@testable import TokenPet

// "Send feedback…" (Feedback.swift): the prefill carries version facts only, is encoded safely,
// stays short enough for GitHub, and the email choice follows the one contact constant.

@Suite struct FeedbackPrefill {
    let env = Feedback.Environment(app: "0.3.4", build: "0.3.4", macOS: "15.5.0",
                                   agents: ["Claude Code", "Codex"])

    @Test func bodyHasTheTemplateAndTheFacts() {
        let b = Feedback.body(env)
        #expect(b.contains("**What happened?**") && b.contains("**What did you expect?**") && b.contains("### Environment"))
        #expect(b.contains("- App: Token Yugong 0.3.4 (build 0.3.4)"))
        #expect(b.contains("- macOS: 15.5.0"))
        #expect(b.contains("- Agents: Claude Code, Codex"))
        #expect(b.utf8.count < Feedback.maxBody)
    }

    @Test func missingFactsLeaveTheirLineOut() {
        let b = Feedback.body(Feedback.Environment(app: "dev", build: "dev", macOS: "14.0.0", agents: []))
        #expect(!b.contains("- Agents:"))
    }

    @Test func nothingFromTheUsersMachineGetsIn() {
        // hostile values in every field: a path, an address, a host name, a URL, a newline
        let bad = Feedback.Environment(app: "/Users/joshua/token-yugong", build: "joshua@example-host.local",
                                       macOS: "15.5\n- Repo: s3onghyun/secret",
                                       agents: ["~/.claude/projects/acme", "branch: main/feature", "https://evil/x?y=z"])
        let b = Feedback.body(bad)
        for leak in ["/", "@", "~", ":/", "?", "=", "\n- Repo"] where b.components(separatedBy: "### Environment")[1].contains(leak) {
            Issue.record("environment block contains \(leak.debugDescription): \(b)")
        }
        #expect(Feedback.body(bad).split(separator: "\n").filter { $0.hasPrefix("- ") }.count == 3)   // App, macOS, Agents: no line was injected

        // what this test machine really reports carries no user, home or host name
        let real = Feedback.body(Feedback.current(family: .standard))
        for secret in [NSUserName(), NSHomeDirectory(), ProcessInfo.processInfo.hostName]
        where secret.count > 2 && real.contains(secret) {
            Issue.record("the prefill contains \(secret)")
        }
        #expect(!real.contains("/Users/"))
    }

    @Test func agentsAreProductNames() {
        #expect(Feedback.agents(.standard) == ["Claude Code", "Codex"])
        #expect(Feedback.agents(Family(roles: [.grandpa: .codex, .son: .gemini])) == ["Codex", "Gemini CLI"])
    }

    @Test func issueURLIsEncoded() throws {
        let url = Feedback.issueURL(env)
        let s = url.absoluteString
        #expect(s.hasPrefix("https://github.com/s3onghyun/token-yugong/issues/new?title=Feedback%3A%20&body="))
        #expect(!s.contains(" ") && !s.contains("\n") && !s.contains("+") && !s.contains("*"))
        #expect(s.contains("%0A") && s.contains("%2A%2AWhat%20happened%3F%2A%2A"))
        #expect(s.contains("Claude%20Code%2C%20Codex"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.map(\.name) == ["title", "body"])
        #expect(items.first { $0.name == "body" }?.value == Feedback.body(env))   // decodes back exactly
        #expect(s.utf8.count < 8000)
    }

    @Test func encodingKeepsOnlyUnreservedCharacters() {
        #expect(Feedback.encode("a b&c=d+e/f?g#h") == "a%20b%26c%3Dd%2Be%2Ff%3Fg%23h")
        #expect(Feedback.encode("의견") == "%EC%9D%98%EA%B2%AC")
        #expect(Feedback.encode("A-z_0.9~") == "A-z_0.9~")
    }

    @Test func mailURLIsEncoded() throws {
        let url = try #require(Feedback.mailURL(env, to: "someone@example.com"))
        #expect(url.absoluteString.hasPrefix("mailto:someone@example.com?subject=Token%20Yugong%20Feedback%3A%20&body="))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "body" }?.value == Feedback.body(env))
    }

    @Test func emailChoiceFollowsTheContactConstant() {
        #expect(Feedback.choices(email: "") == [.github])            // no address: GitHub only
        #expect(Feedback.choices(email: "  ") == [.github])
        #expect(Feedback.choices(email: "a@b.example") == [.github, .email("a@b.example")])
        #expect(Feedback.choices() == Feedback.choices(email: FeedbackContact.email))
    }

    @Test func shippedContactOffersEmailToTheMaintainer() throws {
        #expect(Feedback.choices() == [.github, .email("s3onghyun.hong@gmail.com")])
        let url = try #require(Feedback.mailURL(env, to: FeedbackContact.email))
        #expect(url.absoluteString.hasPrefix("mailto:s3onghyun.hong@gmail.com?subject=Token%20Yugong%20Feedback%3A%20&body="))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "subject" }?.value == "Token Yugong Feedback: ")
        #expect(items.first { $0.name == "body" }?.value == Feedback.body(env))
    }
}
