import AppKit
import UserNotifications

/// The fallback when the menu bar has no room: a small floating window with the same animated
/// Grandpa and number. Click opens the popover, drag moves it (the place is remembered),
/// right-click offers to hide it.
final class MiniWindow: NSPanel {
    let pet = MiniView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 80, height: 36), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = pet
        pet.setAccessibilityRole(.button)
        if !setFrameUsingName("TokenPetMini") , let s = NSScreen.main {
            let v = s.visibleFrame
            setFrameOrigin(NSPoint(x: v.maxX - frame.width - 16, y: v.maxY - frame.height - 12))
        }
        setFrameAutosaveName("TokenPetMini")
    }

    func update(image: NSImage?, title: String) {
        pet.image = image
        guard title != pet.title else { return }
        pet.title = title
        var f = frame
        f.size.width = pet.fittingWidth
        setFrame(f, display: true)
    }
}

final class MiniView: NSView {
    // Layer-backed: a new frame only swaps the sprite layer's contents (no view redraw), and the
    // title layer changes only when the text does. This keeps the mini window as cheap as the bar item.
    private let sprite = CALayer(), label = CATextLayer()
    var image: NSImage? {
        didSet {
            guard image !== oldValue else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            sprite.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            CATransaction.commit()
        }
    }
    var title = "" {
        didSet {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            label.string = title.trimmingCharacters(in: .whitespaces)
            CATransaction.commit()
            needsLayout = true
        }
    }
    var onClick: ((NSView) -> Void)?
    var onHide: (() -> Void)?
    var onWindow: (() -> Void)?
    private var dragged = false
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        sprite.magnificationFilter = .nearest
        label.font = Self.font; label.fontSize = 13
        label.alignmentMode = .left
        layer?.addSublayer(sprite); layer?.addSublayer(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {   // colours follow light and dark mode
        guard let l = layer else { return }
        l.cornerRadius = 10
        l.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        l.borderColor = NSColor.separatorColor.cgColor; l.borderWidth = 1
        label.foregroundColor = NSColor.labelColor.cgColor
        label.contentsScale = window?.backingScaleFactor ?? 2
        sprite.contentsScale = label.contentsScale
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        sprite.frame = CGRect(x: 6, y: (bounds.height - 28) / 2, width: 28, height: 28)
        let h = ceil(Self.font.ascender - Self.font.descender)
        label.frame = CGRect(x: 38, y: (bounds.height - h) / 2, width: max(0, bounds.width - 42), height: h)
        CATransaction.commit()
    }

    var fittingWidth: CGFloat {
        let w = (title.trimmingCharacters(in: .whitespaces) as NSString).size(withAttributes: [.font: Self.font]).width
        return ceil(6 + 28 + (w > 0 ? 4 + w : 0) + 10)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { dragged = false }
    override func mouseDragged(with event: NSEvent) {
        if !dragged { dragged = true; window?.performDrag(with: event) }
    }
    override func mouseUp(with event: NSEvent) { if !dragged { onClick?(self) } }
    override func accessibilityPerformPress() -> Bool { onClick?(self); return true }
    override func accessibilityLabel() -> String? {   // asked each time, so it follows a language change
        L.t("Grandpa Yugong token pet", "우공 할아버지 토큰펫", "愚公じいさんのトークンペット", "愚公爷爷 Token 宠物")
    }

    override func rightMouseDown(with event: NSEvent) {
        let m = NSMenu()
        m.addItem(withTitle: L.t("Show Yugong window", "우공 창으로 보기", "愚公ウィンドウを表示", "显示愚公窗口"),
                  action: #selector(window_), keyEquivalent: "").target = self
        m.addItem(withTitle: L.t("Hide mini window",
                                 "작은 창 숨기기",
                                 "ミニウィンドウを隠す",
                                 "隐藏小窗口"), action: #selector(hide), keyEquivalent: "").target = self
        m.addItem(withTitle: L.t("Quit", "종료", "終了", "退出"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        NSMenu.popUpContextMenu(m, with: event, for: self)
    }
    @objc private func hide() { onHide?() }
    @objc private func window_() { onWindow?() }
}

/// Local notifications. They need the .app bundle; under `swift run` they go to stderr instead.
enum Notify {
    static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func setUp(_ delegate: UNUserNotificationCenterDelegate) {
        guard available else { return }
        UNUserNotificationCenter.current().delegate = delegate
    }

    static func post(id: String, title: String, body: String) {
        guard available else {
            FileHandle.standardError.write("notification: \(title) - \(body)\n".data(using: .utf8)!)
            return
        }
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert]) { ok, _ in
            guard ok else { return }
            let n = UNMutableNotificationContent()
            n.title = title; n.body = body
            c.add(UNNotificationRequest(identifier: id, content: n, trigger: nil))
        }
    }
}
