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
        pet.setAccessibilityLabel(L.t("Grandpa Yugong token pet", "우공 할아버지 토큰펫"))
        if !setFrameUsingName("TokenPetMini") , let s = NSScreen.main {
            let v = s.visibleFrame
            setFrameOrigin(NSPoint(x: v.maxX - frame.width - 16, y: v.maxY - frame.height - 12))
        }
        setFrameAutosaveName("TokenPetMini")
    }

    func update(image: NSImage?, title: String, crisp: Bool) {
        pet.image = image; pet.crisp = crisp
        guard title != pet.title else { return }
        pet.title = title
        var f = frame
        f.size.width = pet.fittingWidth
        setFrame(f, display: true)
    }
}

final class MiniView: NSView {
    var image: NSImage? { didSet { if image !== oldValue { needsDisplay = true } } }
    var title = "" { didSet { needsDisplay = true } }
    var crisp = true
    var onClick: ((NSView) -> Void)?
    var onHide: (() -> Void)?
    private var dragged = false
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)

    var fittingWidth: CGFloat {
        let w = (title.trimmingCharacters(in: .whitespaces) as NSString).size(withAttributes: [.font: Self.font]).width
        return ceil(6 + 28 + (w > 0 ? 4 + w : 0) + 10)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill(); bg.fill()
        NSColor.separatorColor.setStroke(); bg.stroke()
        NSGraphicsContext.current?.imageInterpolation = crisp ? .none : .high
        image?.draw(in: NSRect(x: 6, y: (bounds.height - 28) / 2, width: 28, height: 28))
        let t = title.trimmingCharacters(in: .whitespaces) as NSString
        let size = t.size(withAttributes: [.font: Self.font])
        t.draw(at: NSPoint(x: 38, y: (bounds.height - size.height) / 2), withAttributes: [.font: Self.font, .foregroundColor: NSColor.labelColor])
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { dragged = false }
    override func mouseDragged(with event: NSEvent) {
        if !dragged { dragged = true; window?.performDrag(with: event) }
    }
    override func mouseUp(with event: NSEvent) { if !dragged { onClick?(self) } }
    override func accessibilityPerformPress() -> Bool { onClick?(self); return true }

    override func rightMouseDown(with event: NSEvent) {
        let m = NSMenu()
        m.addItem(withTitle: L.t("Hide mini window", "작은 창 숨기기"), action: #selector(hide), keyEquivalent: "").target = self
        m.addItem(withTitle: L.t("Quit", "종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        NSMenu.popUpContextMenu(m, with: event, for: self)
    }
    @objc private func hide() { onHide?() }
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
