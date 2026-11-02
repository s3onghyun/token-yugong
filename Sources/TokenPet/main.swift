import AppKit
import Combine
import SwiftUI
import TokenPetAssets

// Usage:
//   TokenPet [--style pixel|ink] [--lang en|ko] [--demo lively|steady|straining|resting|morning|cutscene|cycle] [--open]
//            [--bridge <limits.json>] [--logs <dir>] [--tempo idle|low|high|veryHigh]
//   TokenPet --render <dir>     write popover + sprite-sheet PNGs for every state, then exit
//   TokenPet --scan-report      scan local logs once, print what the pet would show, then exit

setvbuf(stdout, nil, _IOLBF, 0)   // line-buffered, so scripts see "stage window N" at once
let args = CommandLine.arguments
func arg(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
if let lang = arg("--lang") { L.korean = lang == "ko" }

let home = FileManager.default.homeDirectoryForCurrentUser
let bridgeURL = URL(fileURLWithPath: arg("--bridge")
    ?? (ProcessInfo.processInfo.environment["TOKENPET_DIR"].map { $0 + "/limits.json" }
        ?? home.appendingPathComponent(".claude/token-pet/limits.json").path))
let logsRoot = URL(fileURLWithPath: arg("--logs") ?? home.appendingPathComponent(".claude/projects").path)
let model = UsageModel(bridgeURL: bridgeURL, logsRoot: logsRoot, style: arg("--style").flatMap(CharacterStyle.init(rawValue:)))

if let problem = CharacterStyle.validateAssets() {
    FileHandle.standardError.write("asset error: \(problem)\n".data(using: .utf8)!)
}

if args.contains("--scan-report") {
    model.scanNow()
    let s = model.snap, sc = model.scanner
    func t(_ d: Date?) -> String { d.map { Fmt.clock($0) } ?? "-" }
    print(String(format: "scanned %.1f MB in %.2fs; %d usage events", Double(sc.bytesRead) / 1e6, sc.lastScanSeconds, sc.events.count))
    print("claude: " + (s.known ? "official, captured \(t(s.captured))" : "don't know (no usable status-line reading)"))
    if let f = s.five { print("5h: \(Int(f.pct.rounded()))% resets \(t(f.resetsAt))") }
    if let w = s.week { print("week: \(Int(w.pct.rounded()))% resets \(t(w.resetsAt))") }
    if let d = s.daily { print(String(format: "no 5-hour window: today's share %.0f%%, day %@ - %@", d.fill * 100, t(d.dayStart), t(d.dayEnd))) }
    if s.resting { print("resting (\(s.restReason)) until \(s.wakeAt.map { Fmt.clock($0) } ?? "?")") }
    if let p = s.projected { print(String(format: "projected by reset: %.0f%%", p)) }
    if let c = s.codex { print("codex: 5h=\(c.five.map { "\(Int($0.pct.rounded()))%" } ?? "-") week=\(c.week.map { "\(Int($0.pct.rounded()))% resets \(t($0.resetsAt))" } ?? "-") (log line \(t(c.at)))") }
    let paceNow = Date(), settled = paceNow.addingTimeInterval(-300)   // 5 minutes ago: every log line is written
    print(String(format: "pace: %.0f output tokens/min (last 3 min) -> %@ at %.0f; %.0f at %.0f", model.liveRate(now: paceNow), "\(model.pace.level)",
                 paceNow.timeIntervalSince1970, model.liveRate(now: settled), settled.timeIntervalSince1970))
    print("carrier: \(Int((s.carrier * 100).rounded()))%  mountain: \(model.mountain.name) \(Int(((1 - model.mountain.left) * 100).rounded()))% carried (\(Int(model.mountain.tokens)) tokens)")
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
    let ko = L.korean ? "-ko" : ""
    model.demoMountainLeft = 0.62
    for style in CharacterStyle.allCases {
        model.style = style
        for st in PetState.allCases {
            model.setDemo(st)
            let r = ImageRenderer(content: PopoverView(model: model, fixedT: 0.9, now: now).background(Color(nsColor: .windowBackgroundColor)))
            r.scale = 2
            if let img = r.nsImage { png(img, "popover-yugong-\(style.rawValue)-\(st.rawValue)\(ko).png") }
        }
        if style == .pixel {
            model.demoWeeklyOnly = true
            for st in [PetState.lively, .resting] {
                model.setDemo(st)
                let r = ImageRenderer(content: PopoverView(model: model, fixedT: 0.9, now: now).background(Color(nsColor: .windowBackgroundColor)))
                r.scale = 2
                if let img = r.nsImage { png(img, "popover-yugong-pixel-weekly-only-\(st.rawValue)\(ko).png") }
            }
            model.demoWeeklyOnly = false
        }
        model.demoCutscene = true; model.setDemo(.morning)
        let r = ImageRenderer(content: PopoverView(model: model, fixedT: 0.9, now: now, cutsceneT: 0.55).background(Color(nsColor: .windowBackgroundColor)))
        r.scale = 2
        if let img = r.nsImage { png(img, "popover-yugong-\(style.rawValue)-cutscene\(ko).png") }
        model.demoCutscene = false
        // menu-bar strip: every state at actual size (1x) and 4x, on light and dark bars
        let states = PetState.allCases
        let strip = NSImage(size: NSSize(width: CGFloat(states.count) * 110 + 20, height: 230), flipped: true) { _ in
            for (row, bg) in [NSColor(white: 0.93, alpha: 1), NSColor(white: 0.16, alpha: 1)].enumerated() {
                bg.setFill(); NSRect(x: 0, y: CGFloat(row) * 115, width: CGFloat(states.count) * 110 + 20, height: 115).fill()
                for (i, st) in states.enumerated() {
                    let img = style.image(st, t: 0.5, size: 20, menuBar: true, carrier: st == .resting ? 1 : 0.5)
                    NSGraphicsContext.current?.imageInterpolation = .none
                    img.draw(in: NSRect(x: 20 + CGFloat(i) * 110, y: CGFloat(row) * 115 + 10, width: 20, height: 20))
                    img.draw(in: NSRect(x: 20 + CGFloat(i) * 110, y: CGFloat(row) * 115 + 34, width: 80, height: 80))
                }
            }
            return true
        }
        png(strip, "menubar-yugong-\(style.rawValue).png")
    }
    model.demoMountainLeft = nil
}

if let dir = arg("--render") {
    MainActor.assumeIsolated { renderStills(to: URL(fileURLWithPath: dir)) }
    print("rendered stills into \(dir)")
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
                Image(nsImage: bar.image).interpolation(model.style.crisp ? .none : .high)
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    let bar = BarMirror()
    var stage: NSPanel?
    var sharingSink: AnyCancellable?
    var snapSink: AnyCancellable?
    var item: NSStatusItem!
    let popover = NSPopover()
    var animTimer: Timer?
    var cycleTimer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.imagePosition = .imageLeading
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))

        model.captureAllowedForDemo = args.contains("--allow-capture")
        model.demoPace = arg("--tempo").flatMap { a in Pace.Level.allCases.first { "\($0)" == a } }
        if let d = arg("--demo") {
            model.demoMountainLeft = 0.62
            model.demoWeeklyOnly = args.contains("--weekly-only")
            if d == "cycle" { model.demoCycle = true; startCycle() }
            else if d == "cutscene" { model.demoCutscene = true; model.cutsceneStart = Date(); model.setDemo(.morning) }
            else { model.setDemo(PetState(flag: d)) }
        }
        model.start()
        snapSink = model.$snap.sink { [weak self] _ in DispatchQueue.main.async { self?.scheduleAnim() } }
        watchVisibility()
        scheduleAnim()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            print("status item window frame: \(self.item.button?.window?.frame ?? .zero), visible=\(self.item.isVisible)")
        }
        if args.contains("--anim-stats") {   // measurement: menu-bar wakes and redraws per 30 s, drawn even if the bar hides the icon
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                print("anim: \(self.wakeCount) wakes, \(self.drawCount) redraws, paused=\(self.paused), state=\(model.snap.state), tempo=\(model.tempo), speed=\(String(format: "%.2f", model.animSpeed))")
                self.wakeCount = 0; self.drawCount = 0
            }
        }
        if args.contains("--open") {
            popover.behavior = .applicationDefined
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.show() }
        }
    }

    func startCycle() {
        // pixel Yugong (the default) through every state and the milestone, then a glimpse of the ink style
        typealias Beat = (CharacterStyle, PetState, cutscene: Bool, mountain: Double, secs: Double)
        let seq: [Beat] = [(.pixel, .lively, false, 0.62, 4.2), (.pixel, .steady, false, 0.6, 3.4), (.pixel, .straining, false, 0.58, 3.4),
                           (.pixel, .resting, false, 0.57, 3.4), (.pixel, .morning, false, 0.57, 3.4), (.pixel, .morning, true, 0.0, 5.0),
                           (.ink, .lively, false, 0.62, 3.0), (.ink, .resting, false, 0.57, 2.6)]
        var i = 0
        func apply() {
            let b = seq[i % seq.count]
            model.style = b.0; model.demoMountainLeft = b.mountain
            model.demoCutscene = b.cutscene; model.cutsceneStart = b.cutscene ? Date() : nil
            model.setDemo(b.1); scheduleAnim()
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
    }

    // RunCat-style menu bar: each routine loop is drawn once into bitmaps, merged into runs of the
    // same picture, and a one-shot timer wakes only when the picture changes. The timer's interval
    // follows the tempo (the animation clock's speed). Nothing is drawn while the bar is hidden.
    var paused = false
    private var loops: [String: (runs: [(img: NSImage, end: Double)], period: Double)] = [:]
    private var lastImage: NSImage?, lastTitle = ""

    func watchVisibility() {
        let ws = NSWorkspace.shared.notificationCenter
        var screensAsleep = false, sessionAway = false
        let update = { [weak self] in
            guard let self else { return }
            let offScreen = !(self.item.button?.window?.occlusionState.contains(.visible) ?? true) && !args.contains("--anim-stats")
            let hidden = screensAsleep || sessionAway || offScreen
            if hidden != self.paused { self.paused = hidden; self.scheduleAnim() }
        }
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in screensAsleep = true; update() }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in screensAsleep = false; update() }
        ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { _ in sessionAway = true; update() }
        ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { _ in sessionAway = false; update() }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: item.button?.window, queue: .main) { _ in update() }
    }

    func scheduleAnim() {
        animTimer?.invalidate()
        animTimer = nil
        if !paused { tick() }
    }

    private func loop(_ style: CharacterStyle, _ st: PetState, _ tempo: Tempo, night: Bool, carrier: Double) -> (runs: [(img: NSImage, end: Double)], period: Double) {
        let fill = (carrier * 4).rounded() / 4          // the basket changes in quarter steps
        let key = "\(style.rawValue)/\(st.rawValue)/\(tempo.rawValue)/\(night)/\(fill)"
        if let l = loops[key] { return l }
        let period = Motion.period(st, night: night, tempo: tempo)
        let step = 1.0 / 8
        let n = Motion.reduce ? 1 : max(1, Int((period / step).rounded()))
        var runs: [(img: NSImage, end: Double)] = [], prev = ""
        for i in 0..<n {
            let t = Double(i) * step
            let sig = TokenPetAssets.signature(style.art, st, t: t, night: night, tempo: tempo)
            if sig == prev, !runs.isEmpty { runs[runs.count - 1].end = t + step; continue }
            runs.append((raster(style.image(st, t: t, size: 20, menuBar: true, carrier: fill, night: night, tempo: tempo)), t + step))
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
        let l = loop(model.style, s.state, model.tempo, night: model.night, carrier: s.carrier)
        let now = Date.timeIntervalSinceReferenceDate
        let p = l.period.isFinite ? model.phase(at: now).truncatingRemainder(dividingBy: l.period) : 0
        let run = l.runs.first { p < $0.end } ?? l.runs[l.runs.count - 1]
        if run.img !== lastImage {
            lastImage = run.img
            item.button?.image = run.img
            bar.image = run.img
            drawCount += 1
        }
        let title: String
        if !s.known { title = " ?" }
        else if s.resting { title = " " + (s.wakeAt.map { Fmt.clock($0) } ?? "?") }
        else if let d = s.daily { title = " \(Int((d.fill * 100).rounded()))%" }
        else if let m = s.five ?? s.week { title = " \(Int(m.pct.rounded()))%" }
        else { title = "" }
        if title != lastTitle {
            lastTitle = title
            bar.title = title
            item.button?.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            ])
        }
        // wake again when this picture ends, at the current speed (at least 1/30 s, at most 30 s)
        let wait = l.period.isFinite ? min(30, max(1.0 / 30, (run.end - p) / max(0.3, model.animSpeed))) : 30
        animTimer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in self?.tick() }
        animTimer?.tolerance = wait * 0.1
    }

    @objc func toggle() { popover.isShown ? popover.performClose(nil) : show() }

    func show() {
        guard let b = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        applySharing()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
