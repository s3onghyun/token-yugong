import AppKit

/// A release version in SemVer order: MAJOR.MINOR.PATCH, then the prerelease (1.0.0-rc.1 < 1.0.0).
/// A leading "v" is fine and build metadata ("+abc") is ignored. Anything else is nil.
struct SemVer: Comparable, CustomStringConvertible {
    let core: [Int]
    let pre: [String]

    init?(_ text: String) {
        var s = Substring(text.trimmingCharacters(in: .whitespaces))
        if s.first == "v" || s.first == "V" { s = s.dropFirst() }
        if let plus = s.firstIndex(of: "+") { s = s[..<plus] }
        let dash = s.firstIndex(of: "-")
        let nums = s[..<(dash ?? s.endIndex)].split(separator: ".", omittingEmptySubsequences: false)
        let core = nums.compactMap { $0.allSatisfy(\.isASCII) ? Int($0) : nil }
        guard nums.count == 3, core.count == 3, core.allSatisfy({ $0 >= 0 }) else { return nil }
        let pre = dash.map { s[s.index(after: $0)...].split(separator: ".", omittingEmptySubsequences: false).map(String.init) } ?? []
        guard pre.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }) else { return nil }
        self.core = core
        self.pre = pre
    }

    var description: String { core.map(String.init).joined(separator: ".") + (pre.isEmpty ? "" : "-" + pre.joined(separator: ".")) }

    static func < (a: SemVer, b: SemVer) -> Bool {
        if a.core != b.core { return a.core.lexicographicallyPrecedes(b.core) }
        if a.pre.isEmpty || b.pre.isEmpty { return !a.pre.isEmpty && b.pre.isEmpty }   // a release beats its prereleases
        for (x, y) in zip(a.pre, b.pre) where x != y {
            switch (Int(x), Int(y)) {
            case let (i?, j?): return i < j
            case (.some, nil): return true    // numbers sort before words
            case (nil, .some): return false
            case (nil, nil): return x < y
            }
        }
        return a.pre.count < b.pre.count
    }
}

/// The update notice. One HTTPS GET to GitHub's latest-release API, at most once a day (or when asked),
/// with no cookies, no cache and only the headers below. Nothing is downloaded until the user clicks
/// Update: then the release's zip is fetched, checked and swapped in for this app, which restarts.
enum Update {
    static let latestAPI = URL(string: "https://api.github.com/repos/s3onghyun/token-yugong/releases/latest")!
    static let interval: TimeInterval = 86_400

    /// Built from the version, never taken from the API's answer.
    static func page(_ v: SemVer) -> URL { URL(string: "https://github.com/s3onghyun/token-yugong/releases/tag/v\(v)")! }

    /// A failed check counts as the day's check; a clock moved backwards checks again.
    static func isDue(now: Date, last: Date?) -> Bool {
        guard let last else { return true }
        return now < last || now.timeIntervalSince(last) >= interval
    }

    /// The `releases/latest` answer -> its version. Drafts, prereleases and tags that are not versions -> nil.
    static func parse(_ data: Data) -> SemVer? {
        struct Release: Decodable { let tag_name: String; let draft: Bool?; let prerelease: Bool? }
        guard data.count <= 1 << 20, let r = try? JSONDecoder().decode(Release.self, from: data),
              r.draft != true, r.prerelease != true else { return nil }
        return SemVer(r.tag_name)
    }

    /// What to show: a version newer than this one that the user has not skipped.
    static func offer(current: SemVer?, latest: SemVer?, skipped: String?) -> SemVer? {
        guard let current, let latest, current < latest, latest.description != skipped else { return nil }
        return latest
    }

    /// The fixed language header: URLSession would otherwise send the system's languages.
    static func headers(_ v: SemVer) -> [String: String] {
        ["User-Agent": "TokenYugong/\(v)", "Accept": "application/vnd.github+json", "Accept-Language": "en"]
    }

    static let session = URLSession(configuration: .ephemeral)

    enum Status { case checking, upToDate, failed }

    // MARK: Update in place

    /// The release archive (scripts/release-artifacts.sh), built from the version like `page`.
    static func archive(_ v: SemVer) -> URL {
        URL(string: "https://github.com/s3onghyun/token-yugong/releases/download/v\(v)/TokenYugong-\(v)-macos-universal.zip")!
    }
    /// The 0.2.2 archive is 1.6 MB; anything near this is not ours.
    static let maxArchive = 50 << 20
    static let brewCommand = "brew upgrade --cask s3onghyun/tap/token-yugong"

    /// How Update works for this copy. Homebrew's copy is upgraded by brew, so its record stays true.
    enum Route: Equatable { case replace, brew, manual }
    static func route(app: URL, writable: Bool, brewed: Bool) -> Route {
        guard app.pathExtension == "app" else { return .manual }
        return brewed ? .brew : writable ? .replace : .manual
    }
    static var brewed: Bool {
        ["/opt/homebrew", "/usr/local"].contains { FileManager.default.fileExists(atPath: "\($0)/Caskroom/token-yugong") }
    }

    enum Install: Equatable { case working, failed(String) }

    /// The unzipped app may replace this one only with this app's bundle id and exactly the offered version.
    static func acceptable(info: [String: Any]?, id: String?, version: SemVer) -> Bool {
        guard let id, let info, info["CFBundleIdentifier"] as? String == id,
              let v = (info["CFBundleShortVersionString"] as? String).flatMap(SemVer.init) else { return false }
        return v == version
    }

    struct Refused: Error { let message: String }

    /// Checks the downloaded zip and puts its app where `app` is. Throws, leaving `app` as it was, unless
    /// the zip is small, unzips to TokenYugong.app, is `version` of app `id`, and its signature verifies.
    static func install(zip: URL, version: SemVer, id: String?, over app: URL) throws {
        let fm = FileManager.default
        let size = (try? fm.attributesOfItem(atPath: zip.path)[.size] as? Int) ?? nil
        guard let size, size <= maxArchive else { throw Refused(message: "archive size \(size ?? -1)") }
        // same volume as the app, so the swap is a rename
        let dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
        defer { try? fm.removeItem(at: dir) }
        guard run("/usr/bin/ditto", "-x", "-k", zip.path, dir.path) else { throw Refused(message: "unzip") }
        let new = dir.appendingPathComponent("TokenYugong.app")
        let info = NSDictionary(contentsOf: new.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        guard acceptable(info: info, id: id, version: version) else { throw Refused(message: "not \(id ?? "?") \(version)") }
        guard run("/usr/bin/codesign", "--verify", "--deep", "--strict", new.path) else { throw Refused(message: "signature") }
        _ = try fm.replaceItemAt(app, withItemAt: new)
    }

    static func run(_ tool: String, _ args: String...) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}

extension UsageModel {
    /// The running version; nil under `swift run` (no bundle), which never checks.
    var appVersion: SemVer? { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(SemVer.init) }

    var updateOffer: SemVer? {
        checkUpdates ? Update.offer(current: appVersion, latest: latestVersion.flatMap(SemVer.init), skipped: skippedVersion) : nil
    }

    /// Asks GitHub when a day has passed since the last check, or now when `asked` (Settings › Check now).
    func checkForUpdate(asked: Bool = false, now: Date = Date()) {
        let last = (Prefs.store.object(forKey: "update.lastCheck") as? Double).map(Date.init(timeIntervalSince1970:))
        guard checkUpdates, let v = appVersion, updateStatus != .checking, asked || Update.isDue(now: now, last: last) else { return }
        Prefs.store.set(now.timeIntervalSince1970, forKey: "update.lastCheck")
        updateStatus = .checking
        var req = URLRequest(url: Update.latestAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        for (k, value) in Update.headers(v) { req.setValue(value, forHTTPHeaderField: k) }
        Update.session.dataTask(with: req) { data, resp, _ in
            let found = (resp as? HTTPURLResponse)?.statusCode == 200 ? data.flatMap(Update.parse) : nil
            DispatchQueue.main.async { [weak self] in self?.learned(found) }
        }.resume()
    }

    var updateRoute: Update.Route {
        let app = Bundle.main.bundleURL, fm = FileManager.default
        return Update.route(app: app, writable: fm.isWritableFile(atPath: app.path) && fm.isWritableFile(atPath: app.deletingLastPathComponent().path),
                            brewed: Update.brewed)
    }

    /// Update: download, check and swap the app, then quit and open the new one at the same path.
    func installUpdate(_ v: SemVer) {
        guard installStep != .working, let current = appVersion else { return }
        installStep = .working
        let app = Bundle.main.bundleURL, id = Bundle.main.bundleIdentifier
        var req = URLRequest(url: Update.archive(v), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        for (k, value) in Update.headers(current) { req.setValue(value, forHTTPHeaderField: k) }
        Update.session.downloadTask(with: req) { file, resp, _ in
            var failure: String?
            if let file, (resp as? HTTPURLResponse)?.statusCode == 200 {
                do { try Update.install(zip: file, version: v, id: id, over: app) }
                catch { failure = "\(error)" }
            } else { failure = "download" }
            DispatchQueue.main.async { [weak self] in
                guard let failure else { return Self.relaunch(app) }
                FileHandle.standardError.write("update: \(failure)\n".data(using: .utf8)!)
                self?.installStep = .failed(failure)
            }
        }.resume()
    }

    /// A shell waits for this process to end, then opens the app again.
    private static func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; open \"$2\"", "sh", "\(getpid())", app.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    private func learned(_ latest: SemVer?) {
        updateStatus = latest == nil ? .failed : .upToDate
        guard let latest else { return }
        latestVersion = latest.description
        Prefs.store.set(latestVersion, forKey: "update.latest")
        // one notification per new version; the popover row stays until it is updated or skipped
        guard let offer = updateOffer, Prefs.store.string(forKey: "update.notified") != offer.description else { return }
        Prefs.store.set(offer.description, forKey: "update.notified")
        Notify.post(id: "update-\(offer)",
                    title: L.t("Token Yugong \(offer) is out", "새 버전 \(offer)이 나왔어요", "新しいバージョン \(offer) が出ました", "新版本 \(offer) 已发布"),
                    body: L.t("Open Grandpa to update, or skip this version.",
                              "할아버지를 열어 업데이트하거나 이 버전을 건너뛸 수 있어요.",
                              "おじいさんを開いてアップデートするか、このバージョンをスキップできます。",
                              "打开爷爷即可更新，或跳过此版本。"))
    }
}
