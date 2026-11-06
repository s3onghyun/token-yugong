import AppKit
import Combine
import SwiftUI
import TokenPetAssets
import UserNotifications

// Usage:
//   TokenPet [--lang en|ko|ja|zh|pseudo] [--demo lively|steady|straining|resting|morning|cutscene|finale|cycle] [--open]
//            [--bridge <limits.json>] [--logs <dir>] [--tempo idle|low|high|veryHigh] [--visitor wifeDoubting|wifeCheering|zhisou]
//            [--lifetime <tokens>] [--award rank:<0-9>|feat:<name>] [--titles] [--window]
//   TokenPet --render <dir>     write popover + sprite-sheet PNGs for every state, then exit
//   TokenPet --scan-report      scan local logs once, print what the pet would show, then exit
//   TokenPet status|setup ...   the command line for people and agents (CLI.swift), then exit

setvbuf(stdout, nil, _IOLBF, 0)   // line-buffered, so scripts see "stage window N" at once
let args = CommandLine.arguments
func arg(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
if let lang = arg("--lang") {   // this run only; the saved setting stays. "pseudo": the truncation check
    if lang == "pseudo" { L.pseudo = true } else { L.lang = L.resolve(lang) }
}

// $HOME first (Foundation ignores it), so a test can run the app against a throwaway home
let home = ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
let bridgeURL = URL(fileURLWithPath: arg("--bridge")
    ?? (ProcessInfo.processInfo.environment["TOKENPET_DIR"].map { $0 + "/limits.json" }
        ?? home.appendingPathComponent(".claude/token-pet/limits.json").path))
let logsRoot = URL(fileURLWithPath: arg("--logs") ?? home.appendingPathComponent(".claude/projects").path)
if let r = CLI.run(Array(args.dropFirst()), home: home, bridge: bridgeURL) {
    FileHandle.standardOutput.write(Data(r.out.utf8))
    FileHandle.standardError.write(Data(r.err.utf8))
    exit(r.code)
}
let model = UsageModel(bridgeURL: bridgeURL, logsRoot: logsRoot)

if args.contains("--scan-report") {
    model.scanNow()
    let s = model.snap, sc = model.scanner
    func t(_ d: Date?) -> String { d.map { Fmt.clock($0) } ?? "-" }
    print(String(format: "scanned %.1f MB in %.2fs; %d usage events", Double(sc.bytesRead) / 1e6, sc.lastScanSeconds, sc.events.count))
    print("claude: " + (s.known ? "official, captured \(t(s.captured))" : "don't know (no usable status-line reading)"))
    if model.accountNote { print("account change detected") }
    if let f = s.five { print("5h: \(Fmt.pct(f.pct)) resets \(t(f.resetsAt))") }
    if let w = s.week { print("week: \(Fmt.pct(w.pct)) resets \(t(w.resetsAt))") }
    if let d = s.daily { print(String(format: "no 5-hour window: today's share %.0f%%, day %@ - %@", d.fill * 100, t(d.dayStart), t(d.dayEnd))) }
    if s.resting { print("resting until \(s.wakeAt.map { Fmt.clock($0) } ?? "?")") }
    if let p = s.projected { print(String(format: "projected by reset: %.0f%%", p)) }
    print("family: " + Role.allCases.compactMap { r in model.family.roles[r].map { "\(r.rawValue)=\($0.rawValue)" } }.joined(separator: " "))
    for (role, m) in s.members.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
        print("\(role.rawValue): " + (m.fill.map { "\(Int(($0 * 100).rounded()))%" } ?? "don't know") + (m.reading.map { " (reported \(t($0.at)))" } ?? ""))
    }
    let paceNow = Date(), settled = paceNow.addingTimeInterval(-300)   // 5 minutes ago: every log line is written
    print(String(format: "pace: %.0f output tokens/min (last 3 min) -> %@ at %.0f; %.0f at %.0f", model.liveRate(now: paceNow), "\(model.pace.level)",
                 paceNow.timeIntervalSince1970, model.liveRate(now: settled), settled.timeIntervalSince1970))
    print("carrier: \(Int((s.carrier * 100).rounded()))%  mountain: \(model.mountain.name) \(Int(((1 - model.mountain.left) * 100).rounded()))% carried (\(Int(model.mountain.tokens)) tokens)")
    let r = Titles.rank(model.lifetime)
    print("title: \(r >= 0 ? Titles.ladder[r].name() : "none") (\(Int(model.lifetime)) tokens in all); achievements: \(model.titles.feats.keys.map(\.rawValue).sorted().joined(separator: " "))")
    print("state: \(s.known ? "\(s.state)" : "unknown")")
    exit(0)
}

@MainActor func renderStills(to dir: URL) {
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    func png(_ img: NSImage, _ name: String) {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = img.size
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
    }
    let now = Date()
    let ko = L.pseudo ? "-pseudo" : L.lang == .en ? "" : "-\(L.lang.rawValue)"
    model.demoMountainLeft = 0.62
    for st in PetState.allCases {
        model.setDemo(st)
        let r = ImageRenderer(content: PopoverView(model: model, fixedT: 0.9, now: now).background(Color(nsColor: .windowBackgroundColor)))
        r.scale = 2
        if let img = r.nsImage { png(img, "popover-yugong-pixel-\(st.rawValue)\(ko).png") }
    }
    model.demoWeeklyOnly = true
    for st in [PetState.lively, .straining, .resting] {
        model.setDemo(st)
        let r = ImageRenderer(content: PopoverView(model: model, fixedT: 0.9, now: now).background(Color(nsColor: .windowBackgroundColor)))
        r.scale = 2
        if let img = r.nsImage { png(img, "popover-yugong-pixel-weekly-only-\(st.rawValue)\(ko).png") }
    }
    model.demoWeeklyOnly = false
    for (v, st) in [(Visitor.wifeDoubting, PetState.morning), (.wifeCheering, .lively), (.zhisou, .resting)] {
        model.demoVisitor = v; model.setDemo(st)
        let r = ImageRenderer(content: PopoverView(model: model, fixedT: 0.9, now: now).background(Color(nsColor: .windowBackgroundColor)))
        r.scale = 2
        if let img = r.nsImage { png(img, "popover-yugong-pixel-visitor-\(v.rawValue)\(ko).png") }
    }
    model.demoVisitor = nil
    model.demoCutscene = true; model.setDemo(.morning)
    let r = ImageRenderer(content: PopoverView(model: model, fixedT: 0.9, now: now, cutsceneT: 0.55).background(Color(nsColor: .windowBackgroundColor)))
    r.scale = 2
    if let img = r.nsImage { png(img, "popover-yugong-pixel-cutscene\(ko).png") }
    model.demoCutscene = false
    model.demoLifetime = 3e9; model.demoFinale = true; model.setDemo(.morning)
    let rf = ImageRenderer(content: PopoverView(model: model, fixedT: 0.9, now: now, cutsceneT: 0.5).background(Color(nsColor: .windowBackgroundColor)))
    rf.scale = 2
    if let img = rf.nsImage { png(img, "popover-yugong-pixel-finale\(ko).png") }
    model.demoFinale = false
    model.demoLifetime = 380_000_000; model.demoAward(.rank(5)); model.setDemo(.lively)   // matches the demo mountain (62% left)
    let rc = ImageRenderer(content: PopoverView(model: model, fixedT: 0.9, now: now).background(Color(nsColor: .windowBackgroundColor)))
    rc.scale = 2
    if let img = rc.nsImage { png(img, "popover-yugong-pixel-title\(ko).png") }
    model.demoAward(nil)
    let rt = ImageRenderer(content: TitlesView(model: model, scrolls: false).background(Color(nsColor: .windowBackgroundColor)))
    rt.scale = 2
    if let img = rt.nsImage { png(img, "titles\(ko).png") }
    try? TitleCard.png(model)?.write(to: dir.appendingPathComponent("title-card\(ko).png"))
    model.demoLifetime = nil
    // menu-bar strip: every state at actual size (1x) and 4x, on light and dark bars
    let states = PetState.allCases
    let strip = NSImage(size: NSSize(width: CGFloat(states.count) * 110 + 20, height: 230), flipped: true) { _ in
        for (row, bg) in [NSColor(white: 0.93, alpha: 1), NSColor(white: 0.16, alpha: 1)].enumerated() {
            bg.setFill(); NSRect(x: 0, y: CGFloat(row) * 115, width: CGFloat(states.count) * 110 + 20, height: 115).fill()
            for (i, st) in states.enumerated() {
                let img = Yugong.image(st, t: 0.5, size: 20, menuBar: true, carrier: st == .resting ? 1 : 0.5)
                NSGraphicsContext.current?.imageInterpolation = .none
                img.draw(in: NSRect(x: 20 + CGFloat(i) * 110, y: CGFloat(row) * 115 + 10, width: 20, height: 20))
                img.draw(in: NSRect(x: 20 + CGFloat(i) * 110, y: CGFloat(row) * 115 + 34, width: 80, height: 80))
            }
        }
        return true
    }
    png(strip, "menubar-yugong-pixel.png")
    model.demoMountainLeft = nil
    for page in 0..<3 {
        let r = ImageRenderer(content: OnboardingView(model: model, done: {}, page: page).background(Color(nsColor: .windowBackgroundColor)))
        r.scale = 2
        if let img = r.nsImage { png(img, "guide-\(page)\(ko).png") }
    }
    png(TokenPetAssets.appIcon(size: 512), "app-icon.png")
}

if let dir = arg("--render") {
    MainActor.assumeIsolated { renderStills(to: URL(fileURLWithPath: dir)) }
    print("rendered stills into \(dir)")
    exit(0)
}

if let dir = arg("--icon-set") {   // PNGs for iconutil (scripts/bundle.sh)
    let out = URL(fileURLWithPath: dir)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for pt in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = pt * scale
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            TokenPetAssets.appIcon(size: CGFloat(px), t: Double(arg("--icon-t") ?? "") ?? TokenPetAssets.iconMoment)
                .draw(in: NSRect(x: 0, y: 0, width: px, height: px))
            NSGraphicsContext.restoreGraphicsState()
            let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
            try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name))
        }
    }
    print("icon set in \(dir)")
    exit(0)
}

/// Mirror of the status item, so a window-only capture can show it next to the popover.
final class BarMirror: ObservableObject {
    @Published var image = NSImage()
    @Published var title = ""
}

struct StageView: View {
    @ObservedObject var bar: BarMirror
    @ObservedObject var model: UsageModel
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 2) {
                Image(nsImage: bar.image).interpolation(.none)
                Text(bar.title).font(.system(size: 12, weight: .medium).monospacedDigit())
            }
            .padding(.horizontal, 8).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.10)))
            PopoverView(model: model)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
        }
        .padding(12)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let bar = BarMirror()
    var mini: MiniWindow?
    var sceneWindow: SceneWindow?   // the big scene in a window of its own; also the fallback when the bar has no room
    var hint: NSPopover?            // one-time "click Grandpa" hint under the bar item
    var barHidden = false           // the menu-bar item is off-screen or behind the notch
    var guide: NSWindow?
    var sinks: [AnyCancellable] = []
    var stage: NSPanel?
    var sharingSink: AnyCancellable?
    var snapSink: AnyCancellable?
    var item: NSStatusItem!
    let popover = NSPopover()
    var animTimer: Timer?
    var cycleTimer: Timer?
    // AppKit's `NSStatusBarButton.setImage` invalidates its cell even at a fixed item width.
    // Keep the button for its normal click/hover behaviour, but put the frequently changing
    // sprite in a sublayer so a frame swap is compositor-only.
    private let statusSprite = CALayer()
    private let statusText = CATextLayer()

    func applicationDidFinishLaunching(_ note: Notification) {
        // Never use `variableLength` for an animated status item.  Re-measuring it for every
        // sprite frame makes AppKit relayout the status-bar window.  This is wide enough for
        // the fixed 20-point image and the widest supported label (`100%`).
        item = NSStatusBar.system.statusItem(withLength: CGFloat(MenuAnimationPolicy.statusItemWidth))
        item.button?.target = self
        item.button?.action = #selector(toggleFromBar)
        installStatusLayers()
        popover.behavior = .transient
        NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: popover, queue: .main) { [weak self] _ in
            self?.anchorPanel?.orderOut(nil)
        }
        let host = NSHostingController(rootView: PopoverView(model: model))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        model.openGuide = { [weak self] in self?.popover.performClose(nil); self?.showGuide() }
        model.openTitles = { [weak self] in self?.popover.performClose(nil); self?.showTitles() }
        model.openWindow = { [weak self] in self?.popover.performClose(nil); self?.showWindow() }
        model.onAward = { a in Notify.post(id: "award-\(a)", title: L.t("A new title from the magpie", "까치가 새 칭호를 물어 왔어요", "カササギが新しい称号を運んできました", "喜鹊带来了新称号"),
                                           body: a.announcement.replacingOccurrences(of: "\n", with: " ")) }
        model.onLimit = { s in
            guard s.resting else {
                return Notify.post(id: "limit-reset", title: L.t("Grandpa picked up his shovel again", "할아버지가 다시 삽을 들었어요", "おじいさんがまたシャベルを手に取りました", "爷爷又拿起了铁锹"),
                                   body: L.t("The limit has reset. Back to digging!", "한도가 풀렸어요. 다시 파 볼까요!", "リミットがリセットされました。また掘りましょう！", "额度已重置，接着挖吧！"))
            }
            let week = (s.week?.pct ?? 0) >= 100
            let when = s.wakeAt.map { Fmt.clock($0) } ?? "?"
            Notify.post(id: "limit-hit", title: L.t("Grandpa sat down to rest", "할아버지가 쉬러 앉았어요", "おじいさんが腰を下ろして休みます", "爷爷坐下来歇歇了"),
                        body: week ? L.t("The weekly limit is used up. Back to digging at \(when).", "주간 한도를 다 썼어요. \(when)에 다시 퍼요.",
                                         "週間リミットを使い切りました。\(when)にまた掘ります。", "本周额度用完了。\(when) 再接着挖。")
                                   : L.t("The 5-hour limit is used up. Back to digging at \(when).", "5시간 한도를 다 썼어요. \(when)에 다시 퍼요.",
                                         "5時間リミットを使い切りました。\(when)にまた掘ります。", "5 小时额度用完了。\(when) 再接着挖。"))
        }
        Notify.setUp(self)

        model.captureAllowedForDemo = args.contains("--allow-capture")
        model.demoPace = arg("--tempo").flatMap { a in Pace.Level.allCases.first { "\($0)" == a } }
        model.demoVisitor = arg("--visitor").flatMap(Visitor.init(rawValue:))
        model.demoLifetime = arg("--lifetime").flatMap(Double.init)
        if let a = arg("--award") {   // rank:3 or feat:streak7
            let p = a.split(separator: ":").map(String.init)
            model.demoAward(p.first == "rank" ? Int(p.last ?? "").map(Award.rank) : Feat(rawValue: p.last ?? "").map(Award.feat))
        }
        if let d = arg("--demo") {
            model.demoMountainLeft = 0.62
            model.demoWeeklyOnly = args.contains("--weekly-only")
            if d == "cycle" { model.demoCycle = true; startCycle() }
            else if d == "cutscene" { model.demoCutscene = true; model.cutsceneStart = Date(); model.setDemo(.morning) }
            else if d == "finale" { model.demoLifetime = 3e9; model.demoFinale = true; model.cutsceneStart = Date(); model.setDemo(.morning) }
            else { model.setDemo(PetState(flag: d)) }
        }
        model.start()
        snapSink = model.$snap.sink { [weak self] _ in DispatchQueue.main.async { self?.scheduleAnim() } }
        watchVisibility()
        scheduleAnim()
        sinks.append(model.$barText.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.scheduleAnim() } })
        sinks.append(model.$barGrandpa.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.scheduleAnim() } })
        sinks.append(model.$miniMode.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.updateMini() } })
        sinks.append(model.$language.dropFirst().sink { [weak self] _ in   // live: AppKit text built once follows too
            DispatchQueue.main.async { guard let self else { return }; self.guide?.title = self.guideTitle; self.titlesWindow?.title = self.titlesTitle
                self.sceneWindow?.title = self.guideTitle; self.scheduleAnim() }
        })
        sinks.append(model.$mountain.sink { m in DispatchQueue.main.async { AppDelegate.milestoneNotice(m) } })
        let demoRun = arg("--demo") != nil || args.contains("--stage")
        if args.contains("--guide") || (!demoRun && !Prefs.store.bool(forKey: "onboarded")) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.showGuide() }   // the hint follows when it closes
        } else if !demoRun {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.showHint() }   // after checkBar; once per user
        }
        if args.contains("--window") || (!demoRun && model.windowAtLaunch) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.showWindow(activate: args.contains("--window"))
                if let w = self.sceneWindow, args.contains("--window") { print("scene window \(w.windowNumber)") }
            }
        }
        sharingSink = model.$hideFromCapture.sink { [weak self] _ in DispatchQueue.main.async { self?.applySharing() } }
        if args.contains("--stage") {
            let host = NSHostingView(rootView: StageView(bar: bar, model: model))
            let size = host.fittingSize
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.contentView = host
            p.level = .floating
            p.center()
            p.orderFrontRegardless()
            stage = p
            applySharing()
            print("stage window \(p.windowNumber)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.checkBar() }
        if args.contains("--anim-stats") {   // measurement: menu-bar wakes and redraws per 30 s, drawn even if the bar hides the icon
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                print("anim: \(self.wakeCount) wakes, \(self.drawCount) redraws, paused=\(self.paused), state=\(model.snap.state), tempo=\(model.tempo), speed=\(String(format: "%.2f", model.animSpeed))")
                self.wakeCount = 0; self.drawCount = 0
            }
        }
        if args.contains("--titles") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.showTitles() } }
        if args.contains("--open") {
            popover.behavior = .applicationDefined
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.show() }   // after checkBar, so it opens under the mini window when the bar is full
        }
    }

    func startCycle() {
        // Yugong through every state and the milestone
        typealias Beat = (PetState, cutscene: Bool, mountain: Double, secs: Double)
        let seq: [Beat] = [(.lively, false, 0.62, 4.2), (.steady, false, 0.6, 3.4), (.straining, false, 0.58, 3.4),
                           (.resting, false, 0.57, 3.4), (.morning, false, 0.57, 3.4), (.morning, true, 0.0, 5.0)]
        var i = 0
        func apply() {
            let b = seq[i % seq.count]
            model.demoMountainLeft = b.mountain
            model.demoCutscene = b.cutscene; model.cutsceneStart = b.cutscene ? Date() : nil
            model.setDemo(b.0); scheduleAnim()
            cycleTimer = Timer.scheduledTimer(withTimeInterval: b.secs, repeats: false) { _ in i += 1; apply() }
        }
        apply()
    }

    /// Screen-share hiding: windows marked `.none` are left out of screenshots, recordings and
    /// shared screens that go through the window server.
    func applySharing() {
        let t: NSWindow.SharingType = (model.hideFromCapture && !model.captureAllowedForDemo) ? .none : .readOnly
        item.button?.window?.sharingType = t
        popover.contentViewController?.view.window?.sharingType = t
        stage?.sharingType = t
        mini?.sharingType = t
        titlesWindow?.sharingType = t
        sceneWindow?.sharingType = t
    }

    // RunCat-style menu bar: each routine loop is drawn once into bitmaps, merged into runs of the
    // same picture, and a one-shot timer wakes only when the picture changes. The timer's interval
    // follows the tempo (the animation clock's speed). Nothing is drawn while the bar is hidden.
    var paused = false
    private var loops: [String: (runs: [(img: NSImage, end: Double)], period: Double)] = [:]
    private var lastImage: NSImage?, lastTitle = "", barShowsImage = true

    private var screensAsleep = false, sessionAway = false
    // `--low-power` is a measurement hook; regular launches follow the system setting.
    private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled || args.contains("--low-power")

    func watchVisibility() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.screensAsleep = true; self?.updatePaused() }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.screensAsleep = false; self?.updatePaused() }
        ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.sessionAway = true; self?.updatePaused() }
        ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.sessionAway = false; self?.updatePaused() }
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: ProcessInfo.processInfo, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled || args.contains("--low-power")
            self.scheduleAnim()
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in self?.updatePaused() }
        // the bar reshuffles when other apps add items or screens change: look again a moment later
        let recheck: (Notification) -> Void = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.checkBar() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: item.button?.window, queue: .main, using: recheck)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: recheck)
    }

    /// Draw only while someone can see the pet: the bar item or the mini window on screen, display awake.
    func updatePaused() {
        let itemSeen = !barHidden && (item.button?.window?.occlusionState.contains(.visible) ?? true)
        let miniSeen = mini.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false
        let hidden = MenuAnimationPolicy.isPaused(screensAsleep: screensAsleep, sessionAway: sessionAway,
                                                   statusItemVisible: itemSeen, miniWindowVisible: miniSeen,
                                                   measuring: args.contains("--anim-stats"))
        if hidden != paused { paused = hidden; scheduleAnim() }
    }

    /// Is the menu-bar item really on screen? If not, tell the user once and fall back to the mini window.
    func checkBar() {
        guard let f = item.button?.window?.frame else { return }
        let screens = NSScreen.screens.map {
            BarFit.Screen(frame: $0.frame, notch: BarFit.notch(frame: $0.frame, left: $0.auxiliaryTopLeftArea, right: $0.auxiliaryTopRightArea))
        }
        guard var hidden = BarFit.hidden(item: f, screens: screens) else { return }
        if args.contains("--pretend-hidden") { hidden = true }   // demo and testing of the fallback
        if hidden != barHidden || !barChecked { print("menu bar item \(hidden ? "hidden" : "visible"): \(f)") }
        barChecked = true
        if barHidden && !hidden { setStatusSprite(barShowsImage ? lastImage : nil) }   // back in view: show the current frame
        barHidden = hidden
        if hidden && !Prefs.store.bool(forKey: "barHiddenWarned") {
            Prefs.store.set(true, forKey: "barHiddenWarned")
            Notify.post(id: "bar-hidden", title: L.t("No room for Grandpa in the menu bar",
                                                     "메뉴바에 할아버지 자리가 없어요",
                                                     "メニューバーにおじいさんの居場所がありません",
                                                     "菜单栏里没有爷爷的位置了"),
                        body: model.miniMode == .off
                            ? L.t("The menu bar is full, so his icon is hidden. Open the app again to see him.",
                                  "메뉴바가 꽉 차서 아이콘이 가려졌어요. 앱을 다시 열면 보여요.",
                                  "メニューバーがいっぱいでアイコンが隠れています。アプリをもう一度開くと表示されます。",
                                  "菜单栏已满，他的图标被藏起来了。再次打开应用即可看到他。")
                            : L.t("The menu bar is full, so he moved into a small floating window. You can change this in Settings.",
                                  "메뉴바가 꽉 차서 작은 창으로 옮겨 왔어요. 설정에서 바꿀 수 있어요.",
                                  "メニューバーがいっぱいなので、小さなフローティングウィンドウに引っ越しました。設定で変更できます。",
                                  "菜单栏已满，他搬进了一个浮动小窗口。可以在设置中更改。"))
        }
        updateMini()
        updatePaused()
    }
    private var barChecked = false

    func updateMini() {
        let want = model.miniMode.shows(barHidden: barHidden)
        if want, mini == nil {
            let m = MiniWindow()
            m.pet.onClick = { [weak self] v in self?.toggle(from: v) }
            m.pet.onHide = { model.miniMode = .off }
            m.pet.onWindow = { [weak self] in self?.showWindow() }
            m.update(image: lastImage, title: lastTitle)
            mini = m
        }
        if want { mini?.orderFrontRegardless() } else { mini?.orderOut(nil) }
        applySharing()
        updatePaused()
    }

    /// One notification per mountain carried away.
    static func milestoneNotice(_ m: MountainLedger) {
        guard m.cutscenePending, Prefs.store.integer(forKey: "mountain.notified") <= m.index else { return }
        Prefs.store.set(m.index + 1, forKey: "mountain.notified")
        Notify.post(id: "mountain-\(m.index)", title: L.t("\(m.name) is gone!",
                                                          "\(m.name)을 다 옮겼어요!",
                                                          "\(m.name)を運びきりました！",
                                                          "\(m.name)被搬走了！"),
                    body: L.t("Heaven was moved by Grandpa's stubbornness. Open him to watch.",
                              "할아버지 끈기에 하늘이 감동했대요. 눌러서 보세요.",
                              "おじいさんの根気に天が心を打たれました。開いて見てください。",
                              "爷爷的毅力感动了上天。打开看看吧。"))
    }

    var guideTitle: String { L.t("Grandpa Yugong", "우공 할아버지", "愚公じいさん", "愚公爷爷") }

    var titlesWindow: NSWindow?
    var titlesTitle: String { L.t("Titles", "칭호", "称号", "称号") }
    func showTitles() {
        if titlesWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 452, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: TitlesView(model: model))
            w.center()
            titlesWindow = w
        }
        titlesWindow?.title = titlesTitle
        NSApp.activate(ignoringOtherApps: true)
        titlesWindow?.makeKeyAndOrderFront(nil)
        applySharing()
    }

    func showGuide() {
        if guide == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = guideTitle
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: OnboardingView(model: model) { [weak self, weak w] in
                Prefs.store.set(true, forKey: "onboarded"); w?.close(); _ = self
            })
            w.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.showHint() }
            }
            guide = w
        }
        Prefs.store.set(true, forKey: "onboarded")   // shown once by itself; Settings reopens it
        NSApp.activate(ignoringOtherApps: true)
        guide?.makeKeyAndOrderFront(nil)
        applySharing()
    }

    /// Opening the app again (Finder, Spotlight) brings Grandpa up; when the bar has no room for him
    /// (and no mini window to hang the popover from), in the Yugong window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if barHidden && mini?.isVisible != true { showWindow() } else { show() }
        return false
    }

    func showWindow(activate: Bool = true) {
        if sceneWindow == nil { sceneWindow = SceneWindow(model: model) }
        sceneWindow?.title = guideTitle
        sceneWindow?.present(activate: activate)
        applySharing()
    }

    /// Once per user: a small bubble under the bar item saying he can be clicked. Not needed once
    /// the popover has been opened; with no room in the bar, the window opens instead.
    func showHint() {
        guard !Prefs.store.bool(forKey: "barHintShown"), !popover.isShown else { return }
        Prefs.store.set(true, forKey: "barHintShown")
        if barHidden { if mini?.isVisible != true { showWindow() }; return }
        guard let b = item.button, b.window != nil else { return }
        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = NSHostingController(rootView:
            Label(L.t("Click Grandpa to see his mountain", "우공을 눌러 보세요", "おじいさんをクリックしてみてください", "点一下爷爷看看"),
                  systemImage: "hand.point.up.left.fill")
                .font(.callout.weight(.semibold)).padding(12))
        p.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        hint = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak p] in p?.performClose(nil) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) { done([.banner]) }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        DispatchQueue.main.async { _ = self.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false); done() }
    }

    func scheduleAnim() {
        animTimer?.invalidate()
        animTimer = nil
        if !paused { tick() }
    }

    private func loop(_ st: PetState, _ tempo: Tempo, night: Bool, carrier: Double, titles: Int) -> (runs: [(img: NSImage, end: Double)], period: Double) {
        let fill = (carrier * 4).rounded() / 4          // the basket changes in quarter steps
        let key = "\(st.rawValue)/\(tempo.rawValue)/\(night)/\(fill)/\(titles)"
        if let l = loops[key] { return l }
        let period = Motion.period(st, night: night, tempo: tempo)
        let step = 1.0 / 8
        let n = Motion.reduce ? 1 : max(1, Int((period / step).rounded()))
        var runs: [(img: NSImage, end: Double)] = [], prev = ""
        for i in 0..<n {
            let t = Double(i) * step
            let sig = TokenPetAssets.signature(st, t: t, night: night, tempo: tempo)
            if sig == prev, !runs.isEmpty { runs[runs.count - 1].end = t + step; continue }
            runs.append((raster(Yugong.image(st, t: t, size: 20, menuBar: true, carrier: fill, night: night, tempo: tempo, titles: titles)), t + step))
            prev = sig
        }
        if loops.count > 24 { loops.removeAll() }
        let l = (runs: runs, period: Motion.reduce ? .infinity : Double(n) * step)
        loops[key] = l
        return l
    }

    private func raster(_ img: NSImage) -> NSImage {
        let px = Int(img.size.width * 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return img }
        rep.size = img.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(origin: .zero, size: img.size))
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: img.size); out.addRepresentation(rep)
        return out
    }

    var wakeCount = 0, drawCount = 0

    func tick() {
        wakeCount += 1
        let s = model.snap
        let (showImage, title) = BarText.item(model.barText.text(s, cutscene: model.cutsceneDue || model.finaleDue, now: Date()), grandpa: model.barGrandpa)
        let miniVisible = mini?.isVisible == true
        let animate = MenuAnimationPolicy.shouldAnimate(lowPowerMode: lowPowerMode, showsImage: showImage,
                                                         miniWindowVisible: miniVisible, staging: args.contains("--stage"),
                                                         measuring: args.contains("--anim-stats"))
        let needsImage = showImage || miniVisible
        var runImage = lastImage
        var nextFrameWait: TimeInterval?
        if needsImage {
            let l = loop(s.state, model.tempo, night: model.night, carrier: s.carrier, titles: model.rewards)
            let now = Date.timeIntervalSinceReferenceDate
            let p = animate && l.period.isFinite
                ? model.phase(at: now).truncatingRemainder(dividingBy: l.period)
                : MenuAnimationPolicy.staticPoseTime(tempo: model.tempo)
            let run = l.runs.first { p < $0.end } ?? l.runs[l.runs.count - 1]
            runImage = run.img
            if animate { nextFrameWait = min(30, max(1.0 / 30, (run.end - p) / max(0.3, model.animSpeed))) }
        }
        if runImage !== lastImage || showImage != barShowsImage {
            if showImage || showImage != barShowsImage {   // % only: the item has no picture to change
                // a hidden bar item still costs a redraw per frame (measured 3% CPU at "high"): skip it
                if !barHidden || args.contains("--anim-stats") { setStatusSprite(showImage ? runImage : nil) }
                // `bar` backs the optional screenshot stage.  Do not publish SwiftUI state for
                // every menu-bar frame when that stage is closed.
                if stage != nil { bar.image = showImage ? (runImage ?? NSImage()) : NSImage() }
            }
            barShowsImage = showImage
            lastImage = runImage
            if miniVisible, let runImage { mini?.pet.image = runImage }
            drawCount += 1
        }
        if MenuAnimationPolicy.shouldUpdateText(previous: lastTitle, next: title) {
            lastTitle = title
            if stage != nil { bar.title = title }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            statusText.string = title.trimmingCharacters(in: .whitespaces)
            CATransaction.commit()
            mini?.update(image: runImage, title: title)
        }
        // Wake at a distinct pose only.  With no animation (notably Low Power Mode), the
        // only time-sensitive work is the menu-bar clock; percentage-only labels need no
        // more than a five-minute check and snapshots schedule an immediate refresh.
        let showsClock = model.barText == .timeLeft || (s.resting && model.barText != .none)
        let wait = nextFrameWait ?? MenuAnimationPolicy.staticRefreshInterval(showsClock: showsClock)
        animTimer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in self?.tick() }
        animTimer?.tolerance = wait * 0.1
    }

    private func installStatusLayers() {
        guard let button = item.button else { return }
        button.image = nil
        button.title = ""
        button.wantsLayer = true
        guard let layer = button.layer else { return }
        let scale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        statusSprite.frame = NSRect(x: 2, y: 2, width: 20, height: 20)
        statusSprite.contentsGravity = .resize
        statusSprite.magnificationFilter = .nearest
        statusSprite.contentsScale = scale
        statusText.frame = NSRect(x: 24, y: 5, width: CGFloat(MenuAnimationPolicy.statusItemWidth) - 26, height: 15)
        statusText.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusText.fontSize = 12
        statusText.foregroundColor = NSColor.labelColor.cgColor
        statusText.contentsScale = scale
        layer.addSublayer(statusSprite)
        layer.addSublayer(statusText)
    }

    private func setStatusSprite(_ image: NSImage?) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        statusSprite.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        CATransaction.commit()
    }

    @objc func toggleFromBar() { toggle(from: barAnchor()) }

    /// The view to open the popover from after a click in the menu bar: the clicked display's bar
    /// (BarFit.clickAnchor), not wherever the app's own item window sits. nil = the usual anchor.
    private var anchorPanel: NSPanel?
    func barAnchor() -> NSView? {
        let screens = NSScreen.screens.map { (frame: $0.frame, visible: $0.visibleFrame) }
        guard let r = BarFit.clickAnchor(mouse: NSEvent.mouseLocation, item: item.button?.window?.frame ?? .zero, screens: screens)
        else { return nil }
        let p = anchorPanel ?? NSPanel(contentRect: r, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.ignoresMouseEvents = true; p.hasShadow = false
        p.level = .statusBar; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.setFrame(r, display: false)
        p.orderFrontRegardless()
        anchorPanel = p
        return p.contentView
    }
    func toggle(from v: NSView?) { popover.isShown ? popover.performClose(nil) : show(from: v) }

    /// Opens the popover under the bar item, or under the mini window when the bar has no room.
    func show(from v: NSView? = nil) {
        guard let anchor = v ?? ((barHidden && mini?.isVisible == true) ? mini?.pet : item.button) else { return }
        if (model.cutsceneDue || model.finaleDue) && model.cutsceneStart == nil { model.cutsceneStart = Date() }   // play it once from the top
        hint?.performClose(nil); hint = nil
        Prefs.store.set(true, forKey: "barHintShown")   // found him: no hint needed
        NSApp.activate(ignoringOtherApps: true)
        if let screen = anchor.window?.screen ?? NSScreen.main { model.popoverMaxHeight = UsageModel.popoverMaxHeight(screen: screen.visibleFrame.height) }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        print("popover opened at \(popover.contentViewController?.view.window?.frame ?? .zero)")   // scripts check where it went
        applySharing()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
