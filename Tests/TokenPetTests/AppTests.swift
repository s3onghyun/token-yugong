import Foundation
import Testing
@testable import TokenPet

// The v0.1 app logic in LOGIC.md: menu-bar fit, the mini window, settings, the status-line
// setup snippet and the mountain ledger.

@Suite struct MenuBar {
    // This Mac: one 1728 x 1117 screen with a notch; the usable bar areas sit left and right of the camera.
    let left = CGRect(x: 0, y: 1085, width: 764, height: 32)
    let right = CGRect(x: 964, y: 1085, width: 764, height: 32)
    var mac: BarFit.Screen {
        let f = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        return BarFit.Screen(frame: f, notch: BarFit.notch(frame: f, left: left, right: right))
    }

    @Test func notchIsTheGapBetweenTheBarAreas() {
        #expect(mac.notch == CGRect(x: 764, y: 1085, width: 200, height: 32))
        #expect(BarFit.notch(frame: mac.frame, left: nil, right: right) == nil)      // no notch on this screen
    }

    @Test func itemInTheBarIsVisible() {
        #expect(BarFit.hidden(item: CGRect(x: 1300, y: 1084, width: 73, height: 33), screens: [mac]) == false)
    }

    @Test func pushedOffTheLeftEdgeIsHidden() {
        // measured on this Mac with a full menu bar
        #expect(BarFit.hidden(item: CGRect(x: -4316, y: 1084, width: 73, height: 33), screens: [mac]) == true)
    }

    @Test func behindTheNotchIsHidden() {
        #expect(BarFit.hidden(item: CGRect(x: 820, y: 1084, width: 73, height: 33), screens: [mac]) == true)
        // just touching the notch edge, mostly in the bar: visible
        #expect(BarFit.hidden(item: CGRect(x: 960, y: 1084, width: 73, height: 33), screens: [mac]) == false)
    }

    @Test func halfOnScreenCounts() {
        #expect(BarFit.hidden(item: CGRect(x: -36, y: 1084, width: 73, height: 33), screens: [mac]) == false)   // 37 of 73 on screen
        #expect(BarFit.hidden(item: CGRect(x: -38, y: 1084, width: 73, height: 33), screens: [mac]) == true)    // 35 of 73
    }

    @Test func secondScreenWithoutNotch() {
        let ext = BarFit.Screen(frame: CGRect(x: 1728, y: 0, width: 2560, height: 1440), notch: nil)
        #expect(BarFit.hidden(item: CGRect(x: 3000, y: 1407, width: 73, height: 33), screens: [mac, ext]) == false)
    }

    @Test func notPlacedYetSaysNothing() {
        #expect(BarFit.hidden(item: .zero, screens: [mac]) == nil)
    }

    // The menu-bar number: the headline window (5-hour, else weekly) in the chosen style
    // (clock strings depend on the time zone and language, which other tests change in parallel:
    // compare with Fmt.clock, tested on its own; the rule under test is which window and which style)
    @Test func barTextFollowsTheHeadlineAndTheStyle() {
        let now = Date(timeIntervalSince1970: 1_793_636_880)              // Tue 2026-11-03 01:28 KST
        let weekReset = Date(timeIntervalSince1970: 1_794_164_400)       // Mon 2026-11-09 04:00 KST
        var s = Snapshot(); s.known = true
        s.five = Meter(pct: 23.6, resetsAt: now + 3 * 3600 + 12 * 60); s.week = Meter(pct: 40, resetsAt: weekReset)
        #expect(BarText.percent.text(s, cutscene: false, now: now) == "24%")          // 5-hour wins, rounded
        #expect(BarText.timeLeft.text(s, cutscene: false, now: now) == "3h 12m")
        #expect(BarText.resetClock.text(s, cutscene: false, now: now) == Fmt.clock(now + 3 * 3600 + 12 * 60, now: now))
        #expect(BarText.none.text(s, cutscene: false, now: now) == "")
        s.five = nil                                                                  // weekly-only
        #expect(BarText.percent.text(s, cutscene: false, now: now) == "40%")
        #expect(BarText.timeLeft.text(s, cutscene: false, now: now) == "6d 2h")
        #expect(BarText.resetClock.text(s, cutscene: false, now: now) == Fmt.clock(weekReset, now: now))
        s.week = Meter(pct: 40, resetsAt: nil)                                        // no reset time: the percent
        #expect(BarText.timeLeft.text(s, cutscene: false, now: now) == "40%")
    }

    @Test func barTextSpecialCases() {
        let now = Date(timeIntervalSince1970: 1_793_636_880)
        var s = Snapshot()
        #expect(BarText.percent.text(s, cutscene: false, now: now) == "?")            // no data
        #expect(BarText.percent.text(s, cutscene: true, now: now) == "✨")             // a mountain is done
        s.known = true; s.five = Meter(pct: 100, resetsAt: now + 3600); s.resting = true; s.wakeAt = now + 3600
        #expect(BarText.timeLeft.text(s, cutscene: false, now: now) == "1h 0m")       // resting: when he starts again
        #expect(BarText.percent.text(s, cutscene: false, now: now) == "1h 0m")        // the countdown, not a frozen 99%
        #expect(BarText.resetClock.text(s, cutscene: false, now: now) == Fmt.clock(now + 3600, now: now))
        s.wakeAt = nil
        #expect(BarText.percent.text(s, cutscene: false, now: now) == "?")
    }

    @Test func barItemIsNeverEmpty() {
        #expect(BarText.item("24%", grandpa: true) == (true, " 24%"))
        #expect(BarText.item("24%", grandpa: false) == (false, "24%"))
        #expect(BarText.item("", grandpa: true) == (true, ""))                       // Grandpa only
        #expect(BarText.item("", grandpa: false) == (true, ""))                      // nothing chosen: Grandpa stays
    }

    @Test func popoverHeaderDetail() {
        let now = Date(timeIntervalSince1970: 1_793_636_880)
        let weekReset = Date(timeIntervalSince1970: 1_794_164_400)
        var s = Snapshot()
        #expect(BarText.detail(s, now: now) == nil)
        s.known = true; s.week = Meter(pct: 21, resetsAt: weekReset)
        #expect(BarText.detail(s, now: now) == "21% · " + Fmt.clock(weekReset, now: now))   // e.g. "21% · 월 04:00"
        s.week = Meter(pct: 21, resetsAt: nil)
        #expect(BarText.detail(s, now: now) == "21%")
    }

    @Test func miniWindowFollowsTheSetting() {
        #expect(MiniMode.auto.shows(barHidden: true) && !MiniMode.auto.shows(barHidden: false))
        #expect(MiniMode.always.shows(barHidden: false) && MiniMode.always.shows(barHidden: true))
        #expect(!MiniMode.off.shows(barHidden: true))
    }

    @Test func menuAnimationStopsWhenNothingCanBeSeen() {
        #expect(MenuAnimationPolicy.isPaused(screensAsleep: true, sessionAway: false, statusItemVisible: true, miniWindowVisible: false, measuring: false))
        #expect(MenuAnimationPolicy.isPaused(screensAsleep: false, sessionAway: true, statusItemVisible: true, miniWindowVisible: false, measuring: false))
        #expect(MenuAnimationPolicy.isPaused(screensAsleep: false, sessionAway: false, statusItemVisible: false, miniWindowVisible: false, measuring: false))
        #expect(!MenuAnimationPolicy.isPaused(screensAsleep: false, sessionAway: false, statusItemVisible: false, miniWindowVisible: true, measuring: false))
    }

    @Test func lowPowerHoldsOnePoseAndSlowsTheClock() {
        #expect(!MenuAnimationPolicy.shouldAnimate(lowPowerMode: true, showsImage: true, miniWindowVisible: false, staging: false, measuring: false))
        #expect(MenuAnimationPolicy.shouldAnimate(lowPowerMode: false, showsImage: true, miniWindowVisible: false, staging: false, measuring: false))
        #expect(MenuAnimationPolicy.staticRefreshInterval(showsClock: true) == 60)
        #expect(MenuAnimationPolicy.staticRefreshInterval(showsClock: false) == 300)
    }

    @Test func statusItemFramesNeverNeedVariableWidthOrTextUpdates() {
        // Its width covers a 20-point sprite and `100%`, but never changes during animation.
        #expect(MenuAnimationPolicy.statusItemWidth == 72)
        #expect(!MenuAnimationPolicy.shouldUpdateText(previous: " 24%", next: " 24%"))
        #expect(MenuAnimationPolicy.shouldUpdateText(previous: " 24%", next: " 25%"))
    }

    @Test func usageRefreshUsesFileChangesWithASlowFallback() {
        #expect(UsageRefreshPolicy.fallbackInterval == 5 * 60)
        #expect(UsageRefreshPolicy.notificationDebounce == 1)
        #expect(UsageRefreshPolicy.minimumNotificationInterval == 30)
    }
}

@Suite struct SettingsAndSetup {
    @Test func snippetForTheDefaultFolder() throws {
        let home = URL(fileURLWithPath: "/Users/someone")
        let cmd = StatusLineSetup.command(dir: home.appendingPathComponent(".claude/token-pet"), home: home)
        #expect(cmd == "sh ~/.claude/token-pet/statusline-bridge.sh")
        // pasted inside settings.json's top-level object, it is valid JSON with exactly this command
        let o = try #require(try JSONSerialization.jsonObject(with: Data(("{" + StatusLineSetup.snippet(command: cmd) + "}").utf8)) as? [String: Any])
        let sl = try #require(o["statusLine"] as? [String: String])
        #expect(sl == ["type": "command", "command": cmd])
    }

    @Test func snippetForACustomFolderQuotes() throws {
        let cmd = StatusLineSetup.command(dir: URL(fileURLWithPath: "/tmp/it's here"), home: URL(fileURLWithPath: "/Users/someone"))
        #expect(cmd == #"TOKENPET_DIR='/tmp/it'\''s here' sh '/tmp/it'\''s here/statusline-bridge.sh'"#)
        let o = try #require(try JSONSerialization.jsonObject(with: Data(("{" + StatusLineSetup.snippet(command: cmd) + "}").utf8)) as? [String: Any])
        #expect((o["statusLine"] as? [String: String])?["command"] == cmd)
    }

    @Test func installCopiesTheBridge() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tokenpet-install-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(StatusLineSetup.install(into: dir))
        #expect(StatusLineSetup.install(into: dir))     // again: replaces, no error
        let copied = try String(contentsOf: dir.appendingPathComponent("statusline-bridge.sh"), encoding: .utf8)
        #expect(copied.contains("rate_limits"))
    }

    /// Macs before macOS 15 have no jq: the bridge falls back to plutil and saves the same thing.
    @Test func bridgeWorksWithoutJq() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("tokenpet-nojq-\(UUID().uuidString)")
        let bin = tmp.appendingPathComponent("bin"), out = tmp.appendingPathComponent("out")
        defer { try? fm.removeItem(at: tmp) }
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        for (name, path) in [("cat", "/bin/cat"), ("date", "/bin/date"), ("mkdir", "/bin/mkdir"), ("mv", "/bin/mv"), ("plutil", "/usr/bin/plutil")] {
            try fm.createSymbolicLink(at: bin.appendingPathComponent(name), withDestinationURL: URL(fileURLWithPath: path))
        }
        let script = try #require(StatusLineSetup.bundledBridge)
        func run(_ input: String) throws -> String {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = [script.path]
            p.environment = ["TOKENPET_DIR": out.path, "PATH": bin.path]
            let i = Pipe(), o = Pipe(); p.standardInput = i; p.standardOutput = o
            try p.run(); i.fileHandleForWriting.write(Data(input.utf8)); try i.fileHandleForWriting.close(); p.waitUntilExit()
            return String(decoding: o.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }
        let line = try run(#"{"session_id":"secret","model":null,"rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1793620000},"seven_day":{"used_percentage":19,"resets_at":1794164400}}}"#)
        #expect(line == "🐾 5h 42%")
        let saved = try String(contentsOf: out.appendingPathComponent("limits.json"), encoding: .utf8)
        #expect(!saved.contains("secret"))
        let r = try #require(Limits.bridge(Data(saved.utf8), fileDate: Date()))
        #expect(r.five == Meter(pct: 42.5, resetsAt: Date(timeIntervalSince1970: 1_793_620_000)))
        #expect(r.week == Meter(pct: 19, resetsAt: reset))
        _ = try run(#"{"session_id":"s"}"#)
        #expect(try String(contentsOf: out.appendingPathComponent("limits.json"), encoding: .utf8) == saved)   // kept
    }
}

@Suite struct Mountain {
    func store() -> UserDefaults {
        let name = "tokenpet-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
    func ev(_ t: Double, _ n: Int) -> LogScanner.Event { LogScanner.Event(time: Date(timeIntervalSince1970: t), tokens: n, output: 0) }

    @Test func countsEachEventOnceAndSurvivesARestart() {
        let d = store()
        var m = MountainLedger.load(d)
        #expect(m.tokens == 0 && m.index == 0 && !m.cutscenePending)
        m.absorb([ev(10, 100), ev(20, 50)])
        m.absorb([ev(10, 100), ev(20, 50), ev(30, 7)])     // the scanner hands over the same events again
        #expect(m.tokens == 157)
        let again = MountainLedger.load(d)                  // app restarted
        #expect(again.tokens == 157 && again.through == Date(timeIntervalSince1970: 30))
    }

    @Test func aWholeMountainTriggersTheCutsceneOnce() {
        let d = store()
        d.set(1000.0, forKey: "mountain.size")
        var m = MountainLedger.load(d)
        m.absorb([ev(1, 999)])
        #expect(!m.cutscenePending)
        m.absorb([ev(2, 301)])
        #expect(m.cutscenePending && m.left == 0)
        #expect(MountainLedger.load(d).cutscenePending)     // still due after a restart
        m.nextMountain()
        #expect(!m.cutscenePending && m.index == 1 && m.tokens == 300)   // the extra tokens start the next mountain
        let next = MountainLedger.load(d)
        #expect(next.index == 1 && next.tokens == 300 && abs(next.left - 0.7) < 1e-9)
    }
}

@Suite struct YugongWindowPlace {
    let main = CGRect(x: 0, y: 0, width: 1512, height: 944)
    let vertical = CGRect(x: -1080, y: -400, width: 1080, height: 1895)   // portrait monitor at the left

    @Test func staysWhereItWasSaved() {
        let f = CGRect(x: -900, y: 300, width: 320, height: 560)
        #expect(ScenePlace.fit(f, screens: [main, vertical]) == f)   // on the vertical monitor, untouched
        let m = CGRect(x: 600, y: 200, width: 480, height: 700)
        #expect(ScenePlace.fit(m, screens: [main, vertical]) == m)
    }

    @Test func monitorGoneMovesToTheMainScreen() {
        let f = CGRect(x: -900, y: 300, width: 320, height: 560)
        #expect(ScenePlace.fit(f, screens: [main]) == CGRect(x: 1512 - 320 - 20, y: 944 - 560 - 20, width: 320, height: 560))
    }

    @Test func halfOffScreenIsPulledInAndShrunkToFit() {
        #expect(ScenePlace.fit(CGRect(x: 1400, y: 800, width: 320, height: 560), screens: [main]) == CGRect(x: 1192, y: 384, width: 320, height: 560))
        #expect(ScenePlace.fit(CGRect(x: 100, y: 0, width: 480, height: 2000), screens: [main]).height == 944)
        #expect(ScenePlace.fit(CGRect(x: 1, y: 2, width: 3, height: 4), screens: []) == CGRect(x: 1, y: 2, width: 3, height: 4))
    }
}

/// The three displays of the bug report (macOS 26): MacBook, an LG above it, a vertical LG at the left.
@Suite struct MenuBarClick {
    let screens: [(frame: CGRect, visible: CGRect)] = [
        (CGRect(x: 0, y: 0, width: 1728, height: 1117), CGRect(x: 0, y: 0, width: 1728, height: 1085)),
        (CGRect(x: 0, y: 1117, width: 1920, height: 1080), CGRect(x: 0, y: 1117, width: 1920, height: 1050)),
        (CGRect(x: -1080, y: 20, width: 1080, height: 1920), CGRect(x: -1080, y: 20, width: 1080, height: 1890)),
    ]
    let itemOnTheLG = CGRect(x: 1467, y: 2167, width: 75, height: 30)   // where the app's own item window sat

    @Test func clickOnTheItemItselfUsesTheItem() {
        #expect(BarFit.clickAnchor(mouse: CGPoint(x: 1500, y: 2180), item: itemOnTheLG, screens: screens) == nil)
    }

    @Test func clickOnAnotherDisplaysCopyOpensThere() {
        // the MacBook's menu bar, where Control Center draws its copy of the item
        #expect(BarFit.clickAnchor(mouse: CGPoint(x: 1300, y: 1100), item: itemOnTheLG, screens: screens)
                == CGRect(x: 1299, y: 1085, width: 2, height: 32))
        // the vertical monitor's bar
        #expect(BarFit.clickAnchor(mouse: CGPoint(x: -420, y: 1930), item: itemOnTheLG, screens: screens)
                == CGRect(x: -421, y: 1910, width: 2, height: 30))
        // the item window parked off-screen (it reads as hidden): still the clicked bar, not the mini window
        let parked = CGRect(x: -4137, y: 2167, width: 73, height: 30)
        #expect(BarFit.clickAnchor(mouse: CGPoint(x: 1500, y: 2180), item: parked, screens: screens)
                == CGRect(x: 1499, y: 2167, width: 2, height: 30))
    }

    @Test func keyboardOrVoiceOverKeepsTheUsualAnchor() {
        #expect(BarFit.clickAnchor(mouse: CGPoint(x: 800, y: 500), item: itemOnTheLG, screens: screens) == nil)   // mouse not in a bar
        #expect(BarFit.clickAnchor(mouse: CGPoint(x: 9000, y: 9000), item: itemOnTheLG, screens: screens) == nil) // nowhere
    }
}

/// The popover under the mini window (or the bar) never grows past its screen; past that it scrolls.
@Test func popoverFitsItsScreen() {
    #expect(UsageModel.popoverMaxHeight(screen: 1050) == 1010)   // the 1920 x 1080 monitor the cut was seen on
    #expect(UsageModel.popoverMaxHeight(screen: 100) == 200)     // never too small to show the headline
}
