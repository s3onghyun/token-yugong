import AppKit
import Combine
import SwiftUI
import TokenPetAssets

// Usage:
//   TokenPet [--style pixel|ink] [--lang en|ko] [--demo lively|steady|straining|resting|morning|cutscene|cycle] [--open]
//            [--bridge <limits.json>] [--logs <dir>]
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
    print(String(format: "scanned %.1f MB in %.2fs; %d usage events, %d limit hits", Double(sc.bytesRead) / 1e6, sc.lastScanSeconds, sc.events.count, sc.hits.count))
    print("source: \(s.source)")
    if let f = s.five { print("5h: \(Int(f.pct))% tokens=\(f.tokens.map(String.init) ?? "-") resets=\(f.resetsAt.map { Fmt.clock($0) } ?? "-")") }
    if let w = s.week { print("week: \(Int(w.pct))% tokens=\(w.tokens.map(String.init) ?? "-") rolling=\(w.rolling)") }
    if let l = s.learned5h { print("learned 5h ceiling: \(l) tokens") }
    if let h = sc.hits.last { print("last limit hit: \(h.time) kind=\(h.kind) wake=\(h.wake.map { Fmt.clock($0) } ?? "-")") }
    if let c = s.codex { print("codex: 5h=\(c.five.map { "\(Int($0.pct))%" } ?? "-") week=\(c.week.map { "\(Int($0.pct))% resets \($0.resetsAt.map { Fmt.clock($0) } ?? "-")" } ?? "-") (from log at \(c.at))") }
    if let d = s.daily { print(String(format: "no 5-hour window: today's share used %.0f%% (%.1f of %.1f weekly points), day ends %@%@", d.fill * 100, d.usedToday, d.share, Fmt.clock(d.dayEnd), d.estimated ? " (day start estimated)" : "")) }
    print("carrier: \(Int((s.carrier * 100).rounded()))%  mountain: \(model.mountain.name) \(Int(((1 - model.mountain.left) * 100).rounded()))% carried (\(Int(model.mountain.tokens)) tokens)")
    print("state: \(s.state)")
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
    var item: NSStatusItem!
    let popover = NSPopover()
    var frame = 0
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
        if let d = arg("--demo") {
            model.demoMountainLeft = 0.62
            model.demoWeeklyOnly = args.contains("--weekly-only")
            if d == "cycle" { model.demoCycle = true; startCycle() }
            else if d == "cutscene" { model.demoCutscene = true; model.cutsceneStart = Date(); model.setDemo(.morning) }
            else { model.setDemo(PetState(flag: d)) }
        }
        model.start()
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

    func scheduleAnim() {
        animTimer?.invalidate()
        animTimer = Timer.scheduledTimer(withTimeInterval: 1 / model.menuBarFPS, repeats: true) { [weak self] _ in self?.tick() }
        animTimer?.tolerance = 0.2 / model.menuBarFPS
        tick()
    }

    private var lastState: PetState?
    private var loops: [String: [NSImage]] = [:]
    private var lastIndex = -1, lastTitle = ""

    /// One routine loop per (style, state, night, carrier level), drawn once into bitmaps and then replayed.
    private func loop(_ style: CharacterStyle, _ st: PetState, fps: Double, night: Bool, carrier: Double) -> [NSImage] {
        let fill = (carrier * 4).rounded() / 4          // the basket changes in quarter steps
        let key = "\(style.rawValue)/\(st.rawValue)/\(fps)/\(night)/\(fill)"
        if let l = loops[key] { return l }
        let n = Motion.reduce ? 1 : max(1, Int((Motion.period(st, night: night) * fps).rounded()))
        // identical consecutive poses share one image, so tick() can skip the redraw
        var l: [NSImage] = [], prev = ""
        for i in 0..<n {
            let t = Double(i) / fps
            let sig = TokenPetAssets.signature(style.art, st, t: t, night: night)
            if sig == prev, let last = l.last { l.append(last) }
            else { l.append(raster(style.image(st, t: t, size: 20, menuBar: true, carrier: fill, night: night))) }
            prev = sig
        }
        if loops.count > 24 { loops.removeAll() }
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

    func tick() {
        frame += 1
        let s = model.snap
        if s.state != lastState { lastState = s.state; lastIndex = -1; scheduleAnim(); return }
        let fps = model.menuBarFPS
        let frames = loop(model.style, s.state, fps: fps, night: model.night, carrier: s.carrier)
        let idx = Int(Date.timeIntervalSinceReferenceDate * fps) % frames.count
        if idx != lastIndex && item.button?.image !== frames[idx] {
            lastIndex = idx
            item.button?.image = frames[idx]
            bar.image = frames[idx]
        }
        let title: String
        if s.state == .resting, let w = s.sleepUntil { title = " " + Fmt.clock(w) }
        else if let d = s.daily { title = " \(Int((d.fill * 100).rounded()))%" }
        else if let f = s.five { title = " \(Int(f.pct.rounded()))%" }
        else { title = "" }
        guard title != lastTitle else { return }
        lastTitle = title
        bar.title = title
        item.button?.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        ])
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
