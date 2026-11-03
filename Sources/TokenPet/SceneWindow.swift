import AppKit
import SwiftUI

/// Where the Yugong window sits: a normal window, above every window, or down on the desktop.
enum SceneLevel: String, CaseIterable {
    case normal, onTop, desktop
}

/// A remembered frame that still fits the screens of today. Kept on the screen it overlaps most
/// (moved fully inside it); a screen that is gone (the vertical monitor unplugged) sends it to the
/// main screen, top right. `screens` are visible frames, the main screen first.
enum ScenePlace {
    static func fit(_ f: CGRect, screens: [CGRect]) -> CGRect {
        guard let main = screens.first else { return f }
        func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
        let best = screens.max { area($0.intersection(f)) < area($1.intersection(f)) } ?? main
        let s = area(best.intersection(f)) > 0 ? best : main
        var r = f
        r.size = CGSize(width: min(f.width, s.width), height: min(f.height, s.height))
        if s != best || area(best.intersection(f)) == 0 { r.origin = CGPoint(x: s.maxX - r.width - 20, y: s.maxY - r.height - 20) }
        r.origin.x = min(max(r.minX, s.minX), s.maxX - r.width)
        r.origin.y = min(max(r.minY, s.minY), s.maxY - r.height)
        return r
    }
}

/// Whether anyone can see the window: when no one can, the scene stops animating.
final class SceneVisibility: ObservableObject {
    @Published var shown = false
}

/// The popover's content, scaled to the window's width.
struct SceneWindowView: View {
    @ObservedObject var model: UsageModel
    @ObservedObject var vis: SceneVisibility
    var natural: (CGSize) -> Void = { _ in }

    var body: some View {
        GeometryReader { g in
            // hidden or covered: a still picture, so the scene's 8 fps timeline stops
            PopoverView(model: model, fixedT: vis.shown ? nil : model.phase(at: Date.timeIntervalSinceReferenceDate), inWindow: true)
                .fixedSize()
                .background(GeometryReader { p in Color.clear.onAppear { natural(p.size) }.onChange(of: p.size, perform: natural) })
                .scaleEffect(g.size.width / SceneWindow.baseWidth, anchor: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The big scene in a window of its own: resizable (the content scales, keeping its proportions),
/// draggable, Esc or the close button hides it. Size, place, level and opacity are remembered.
final class SceneWindow: NSPanel, NSWindowDelegate, NSMenuDelegate {
    static let baseWidth: CGFloat = 320          // PopoverView's width
    static let sizes: [CGFloat] = [240, 320, 480] // small, medium, large
    let vis = SceneVisibility()
    private var natural = CGSize(width: baseWidth, height: 560)
    private let pullDown = NSMenu()

    init(model: UsageModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.baseWidth, height: 560),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        delegate = self
        let host = NSHostingView(rootView: SceneWindowView(model: model, vis: vis) { [weak self] in self?.naturalChanged($0) })
        host.sizingOptions = []   // the window's width sets the scale, not the content
        contentView = host
        pullDown.delegate = self
        let menu = NSMenu(); menu.delegate = self
        let more = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 34, height: 22), pullsDown: true)
        more.isBordered = false
        more.menu = pullDown
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = more
        accessory.layoutAttribute = .trailing
        addTitlebarAccessoryViewController(accessory)
        host.menu = menu   // right-click anywhere shows the same options
        menuNeedsUpdate(pullDown)
        if let s = Prefs.store.string(forKey: "sceneWindow.frame") { setFrame(NSRectFromString(s), display: false) } else { center() }
        applyPrefs()
    }

    var place: SceneLevel {
        get { SceneLevel(rawValue: Prefs.store.string(forKey: "sceneWindow.level") ?? "") ?? .normal }
        set { Prefs.store.set(newValue.rawValue, forKey: "sceneWindow.level"); applyPrefs() }
    }
    var opacity: Double {
        get { Prefs.store.object(forKey: "sceneWindow.opacity") as? Double ?? 1 }
        set { Prefs.store.set(newValue, forKey: "sceneWindow.opacity"); applyPrefs() }
    }

    private func applyPrefs() {
        alphaValue = opacity
        switch place {
        case .normal: level = .normal; collectionBehavior = [.fullScreenAuxiliary]
        case .onTop: level = .floating; collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        case .desktop:   // just above the desktop icons, under every app window, on every Space
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            collectionBehavior = [.canJoinAllSpaces, .stationary]
        }
    }

    /// Back on a screen that exists (a monitor may be gone since it was saved), then in front.
    func present(activate: Bool) {
        setFrame(fitted(frame), display: false)
        if activate { NSApp.activate(ignoringOtherApps: true); makeKeyAndOrderFront(nil) } else { orderFrontRegardless() }
        updateVisibility()
    }

    private func fitted(_ f: NSRect) -> NSRect {
        let screens = (NSScreen.main.map { [$0] } ?? []) + NSScreen.screens.filter { $0 != NSScreen.main }
        return ScenePlace.fit(f, screens: screens.map(\.visibleFrame))
    }

    /// The content's own size changed (settings opened, a family row added): same width, new height.
    private func naturalChanged(_ n: CGSize) {
        guard n.width > 0, n.height > 0, n != natural else { return }
        natural = n
        contentAspectRatio = n
        contentMinSize = NSSize(width: Self.sizes[0] * 0.8, height: Self.sizes[0] * 0.8 * n.height / n.width)
        setWidth(contentLayoutRect.width)
    }

    func setWidth(_ w: CGFloat) {
        var f = frame
        let content = NSSize(width: w, height: (w * natural.height / natural.width).rounded())
        let size = frameRect(forContentRect: NSRect(origin: .zero, size: content)).size
        f.origin.y += f.height - size.height   // keep the top edge where it is
        f.size = size
        setFrame(fitted(f), display: true, animate: isVisible)
        save()
    }

    private func save() { Prefs.store.set(NSStringFromRect(frame), forKey: "sceneWindow.frame") }
    private func updateVisibility() {
        let v = isVisible && occlusionState.contains(.visible)
        if v != vis.shown { vis.shown = v }
    }

    override func cancelOperation(_ sender: Any?) { close() }   // Esc
    func windowDidMove(_ n: Notification) { save() }
    func windowDidEndLiveResize(_ n: Notification) { save() }
    func windowDidChangeOcclusionState(_ n: Notification) { updateVisibility() }
    func windowWillClose(_ n: Notification) { vis.shown = false }

    // The ⋯ button and the right-click menu, rebuilt each time so the language and the ticks are current.
    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        if m === pullDown { m.addItem(withTitle: "", action: nil, keyEquivalent: "").image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil) }   // a pull-down shows its first item as the button
        func item(_ title: String, on: Bool, _ act: @escaping () -> Void) {
            let i = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: "")
            i.target = self; i.state = on ? .on : .off; i.representedObject = act
            m.addItem(i)
        }
        let w = contentLayoutRect.width
        for (s, name) in zip(Self.sizes, [L.t("Small", "작게", "小", "小"), L.t("Medium", "보통", "中", "中"), L.t("Large", "크게", "大", "大")]) {
            item(name, on: abs(w - s) < 1) { [weak self] in self?.setWidth(s) }
        }
        m.addItem(.separator())
        for (l, name) in [(SceneLevel.normal, L.t("Normal window", "보통 창", "通常のウィンドウ", "普通窗口")),
                          (.onTop, L.t("Always on top", "항상 위에", "常に手前に表示", "始终置顶")),
                          (.desktop, L.t("On the desktop", "바탕화면에 두기", "デスクトップに置く", "放在桌面上"))] {
            item(name, on: place == l) { [weak self] in self?.place = l }
        }
        m.addItem(.separator())
        for a in [1.0, 0.85, 0.7, 0.5] {
            item(L.t("Opacity \(Int(a * 100))%", "불투명도 \(Int(a * 100))%", "不透明度 \(Int(a * 100))%", "不透明度 \(Int(a * 100))%"), on: abs(opacity - a) < 0.01) { [weak self] in self?.opacity = a }
        }
        m.addItem(.separator())
        item(L.t("Close (Esc)", "닫기 (Esc)", "閉じる（Esc）", "关闭（Esc）"), on: false) { [weak self] in self?.close() }
    }
    @objc private func run(_ i: NSMenuItem) { (i.representedObject as? () -> Void)?() }
}
