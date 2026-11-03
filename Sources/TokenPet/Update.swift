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
/// with no cookies, no cache and only the headers below. Nothing is downloaded or installed: the notice
/// opens the release page, and the user replaces the app as on the first install (README).
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
        ["User-Agent": "YugongPet/\(v)", "Accept": "application/vnd.github+json", "Accept-Language": "en"]
    }

    static let session = URLSession(configuration: .ephemeral)

    enum Status { case checking, upToDate, failed }
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

    private func learned(_ latest: SemVer?) {
        updateStatus = latest == nil ? .failed : .upToDate
        guard let latest else { return }
        latestVersion = latest.description
        Prefs.store.set(latestVersion, forKey: "update.latest")
        // one notification per new version; the popover row stays until it is updated or skipped
        guard let offer = updateOffer, Prefs.store.string(forKey: "update.notified") != offer.description else { return }
        Prefs.store.set(offer.description, forKey: "update.notified")
        Notify.post(id: "update-\(offer)",
                    title: L.t("Yugong Pet \(offer) is out", "새 버전 \(offer)이 나왔어요", "新しいバージョン \(offer) が出ました", "新版本 \(offer) 已发布"),
                    body: L.t("Open Grandpa to see the release page, or skip this version.",
                              "할아버지를 열어 릴리스 페이지를 보거나 이 버전을 건너뛸 수 있어요.",
                              "おじいさんを開いてリリースページを見るか、このバージョンをスキップできます。",
                              "打开爷爷可查看发布页面，或跳过此版本。"))
    }
}
