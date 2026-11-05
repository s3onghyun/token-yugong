import Foundation
import Testing
@testable import TokenPet

// The update notice (Update.swift): version order, the once-a-day check, what GitHub's answer means.

@Suite struct UpdateNotice {
    func v(_ s: String) -> SemVer { SemVer(s)! }

    @Test func versionsCompareAsNumbers() {
        #expect(v("0.10.0") > v("0.9.9"))           // not as text
        #expect(v("1.0.0") > v("0.99.99"))
        #expect(v("0.2.1") > v("0.2.0"))
        #expect(v("v0.3.0") == v("0.3.0"))          // tags carry a "v"
        #expect(v("0.3.0+build.7") == v("0.3.0"))   // build metadata does not count
        #expect(v("0.3.0").description == "0.3.0" && v("v1.2.3-rc.1").description == "1.2.3-rc.1")
    }

    @Test func prereleasesComeBeforeTheRelease() {
        #expect(v("1.0.0-rc.1") < v("1.0.0"))
        #expect(v("1.0.0-rc.2") < v("1.0.0-rc.10"))      // numeric identifiers as numbers
        #expect(v("1.0.0-alpha") < v("1.0.0-alpha.1"))   // fewer identifiers first
        #expect(v("1.0.0-1") < v("1.0.0-alpha"))         // numbers before words
        #expect(v("1.0.0-alpha") < v("1.0.0-beta"))
        #expect(v("0.9.0") < v("1.0.0-rc.1"))
    }

    @Test func notVersions() {
        for s in ["", "dev", "1.2", "1.2.3.4", "1..3", "a.b.c", "1.2.x", "1.2.3-", "1.2.3-rc..1", "1.2.-3", "latest", "1.2.3-ünï"] {
            #expect(SemVer(s) == nil, "\(s)")
        }
    }

    @Test func atMostOnceADay() {
        let t = Date(timeIntervalSince1970: 1_793_600_000)
        #expect(Update.isDue(now: t, last: nil))                       // never asked
        #expect(!Update.isDue(now: t + 60, last: t))
        #expect(!Update.isDue(now: t + 86_399, last: t))
        #expect(Update.isDue(now: t + 86_400, last: t))
        #expect(Update.isDue(now: t - 3600, last: t))                  // clock moved back: ask again
    }

    @Test func readsTheLatestRelease() {
        func json(_ tag: String, draft: Bool = false, pre: Bool = false) -> Data {
            Data(#"{"tag_name":"\#(tag)","draft":\#(draft),"prerelease":\#(pre),"html_url":"https://evil.example/","body":"x"}"#.utf8)
        }
        #expect(Update.parse(json("v0.3.0")) == v("0.3.0"))
        #expect(Update.parse(json("v0.3.0", draft: true)) == nil)
        #expect(Update.parse(json("v0.4.0-rc.1", pre: true)) == nil)
        #expect(Update.parse(json("nightly")) == nil)
        #expect(Update.parse(Data("{\"message\":\"API rate limit exceeded\"}".utf8)) == nil)
        #expect(Update.parse(Data(count: (1 << 20) + 1)) == nil)
        // the page is built from the version, whatever html_url said
        #expect(Update.page(v("0.3.0")).absoluteString == "https://github.com/s3onghyun/token-yugong/releases/tag/v0.3.0")
    }

    @Test func offersOnlyANewerUnskippedVersion() {
        #expect(Update.offer(current: v("0.2.0"), latest: v("0.3.0"), skipped: nil) == v("0.3.0"))
        #expect(Update.offer(current: v("0.2.0"), latest: v("0.3.0"), skipped: "0.3.0") == nil)
        #expect(Update.offer(current: v("0.2.0"), latest: v("0.3.1"), skipped: "0.3.0") == v("0.3.1"))   // a newer one shows again
        #expect(Update.offer(current: v("0.3.0"), latest: v("0.3.0"), skipped: nil) == nil)
        #expect(Update.offer(current: v("0.4.0"), latest: v("0.3.0"), skipped: nil) == nil)             // never offers a downgrade
        #expect(Update.offer(current: nil, latest: v("0.3.0"), skipped: nil) == nil)                     // swift run: no version
    }

    /// Nothing about the user goes out: no system language, no identifiers.
    @Test func sendsOnlyFixedHeaders() {
        #expect(Update.headers(v("0.2.0")) == ["User-Agent": "TokenYugong/0.2.0", "Accept": "application/vnd.github+json", "Accept-Language": "en"])
        #expect(Update.latestAPI.absoluteString == "https://api.github.com/repos/s3onghyun/token-yugong/releases/latest")
    }

    @Test func archiveIsBuiltFromTheVersion() {
        #expect(Update.archive(v("0.2.3")).absoluteString
                == "https://github.com/s3onghyun/token-yugong/releases/download/v0.2.3/TokenYugong-0.2.3-macos-universal.zip")
    }

    @Test func routeForThisCopy() {
        let app = URL(fileURLWithPath: "/Applications/TokenYugong.app")
        #expect(Update.route(app: app, writable: true, brewed: false) == .replace)
        #expect(Update.route(app: app, writable: true, brewed: true) == .brew)        // brew keeps its own record
        #expect(Update.route(app: app, writable: false, brewed: false) == .manual)
        #expect(Update.route(app: URL(fileURLWithPath: "/tmp/.build/debug"), writable: true, brewed: false) == .manual)   // swift run
    }

    @Test func acceptsOnlyThisAppAtTheOfferedVersion() {
        let id = "dev.yugongpet.app"
        func info(_ i: String, _ ver: String) -> [String: Any] { ["CFBundleIdentifier": i, "CFBundleShortVersionString": ver] }
        #expect(Update.acceptable(info: info(id, "0.2.3"), id: id, version: v("0.2.3")))
        #expect(!Update.acceptable(info: info(id, "0.2.2"), id: id, version: v("0.2.3")))         // not what was offered
        #expect(!Update.acceptable(info: info("evil.app", "0.2.3"), id: id, version: v("0.2.3")))
        #expect(!Update.acceptable(info: nil, id: id, version: v("0.2.3")))
        #expect(!Update.acceptable(info: info(id, "0.2.3"), id: nil, version: v("0.2.3")))          // swift run has no id
    }

    /// The real swap on a fake app: a matching signed zip replaces it; anything else leaves it alone.
    @Test func installReplacesOnlyWithAVerifiedApp() throws {
        let fm = FileManager.default, id = "dev.yugongpet.test"
        let root = fm.temporaryDirectory.appendingPathComponent("update-\(UUID())")
        defer { try? fm.removeItem(at: root) }
        func makeApp(_ dir: String, version: String, sign: Bool) throws -> URL {
            let app = root.appendingPathComponent(dir).appendingPathComponent("TokenYugong.app")
            try fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            try fm.copyItem(atPath: "/usr/bin/true", toPath: app.appendingPathComponent("Contents/MacOS/TokenPet").path)
            (["CFBundleIdentifier": id, "CFBundleShortVersionString": version, "CFBundleExecutable": "TokenPet"] as NSDictionary)
                .write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
            if sign { #expect(Update.run("/usr/bin/codesign", "--force", "--sign", "-", app.path)) }
            return app
        }
        func zip(_ app: URL) -> URL {
            let z = app.deletingLastPathComponent().appendingPathComponent("a.zip")
            #expect(Update.run("/usr/bin/ditto", "-c", "-k", "--keepParent", app.path, z.path))
            return z
        }
        func installed(_ app: URL) -> String? {
            NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
        }
        let current = try makeApp("installed", version: "0.2.2", sign: true)

        #expect(throws: Update.Refused.self) { try Update.install(zip: zip(try makeApp("old", version: "0.2.1", sign: true)), version: v("0.2.3"), id: id, over: current) }
        #expect(throws: Update.Refused.self) { try Update.install(zip: zip(try makeApp("unsigned", version: "0.2.3", sign: false)), version: v("0.2.3"), id: id, over: current) }
        #expect(throws: Update.Refused.self) { try Update.install(zip: zip(try makeApp("other", version: "0.2.3", sign: true)), version: v("0.2.3"), id: "dev.other", over: current) }
        #expect(installed(current) == "0.2.2")

        try Update.install(zip: zip(try makeApp("new", version: "0.2.3", sign: true)), version: v("0.2.3"), id: id, over: current)
        #expect(installed(current) == "0.2.3")
        #expect(Update.run("/usr/bin/codesign", "--verify", "--deep", "--strict", current.path))
    }
}
