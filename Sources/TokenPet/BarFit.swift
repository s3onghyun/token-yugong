import Foundation

/// Is the menu-bar item where the user can see it? When the bar is full, macOS pushes extra items
/// off the left edge of the screen (measured here: x = -4316 on a 1728-point screen) or behind the
/// camera notch. Pure geometry, in screen coordinates, so it has unit tests (LOGIC.md, "Menu bar").
enum BarFit {
    struct Screen {
        var frame: CGRect
        var notch: CGRect?      // the strip of the menu bar the camera housing covers, if any
    }

    /// nil = not placed yet (empty frame), so nothing can be said.
    static func hidden(item: CGRect, screens: [Screen]) -> Bool? {
        guard item.width > 0, item.height > 0 else { return nil }
        // at least half of the item must sit on some screen ...
        guard let s = screens.first(where: { $0.frame.intersection(item).width * 2 >= item.width }) else { return true }
        // ... and not mostly under that screen's notch
        if let n = s.notch, n.intersection(item).width * 2 > item.width { return true }
        return false
    }

    /// Where a click on the menu-bar item should open the popover. macOS 26 draws status items as
    /// Control Center copies in the menu bar of every display, while the app's own item window stays
    /// on one display (or parked off-screen when it reads as hidden), so a popover anchored to that
    /// window opens on another display than the one clicked, or under the mini window. nil = the
    /// mouse is on the item itself (or not in any menu bar: keyboard, VoiceOver), use the item as
    /// before; else a thin anchor at the mouse, spanning that screen's menu bar.
    static func clickAnchor(mouse: CGPoint, item: CGRect, screens: [(frame: CGRect, visible: CGRect)]) -> CGRect? {
        if item.insetBy(dx: -2, dy: -2).contains(mouse) { return nil }
        guard let s = screens.first(where: { $0.frame.contains(mouse) }) else { return nil }
        let bar = s.frame.maxY - s.visible.maxY > 0 ? s.frame.maxY - s.visible.maxY : 24   // auto-hidden bar: no inset
        guard mouse.y >= s.frame.maxY - bar else { return nil }
        return CGRect(x: mouse.x - 1, y: s.frame.maxY - bar, width: 2, height: bar)
    }

    /// The notch strip from NSScreen's auxiliary areas (macOS 12+): the gap between the usable
    /// menu-bar areas left and right of the camera.
    static func notch(frame: CGRect, left: CGRect?, right: CGRect?) -> CGRect? {
        guard let l = left, let r = right, r.minX > l.maxX else { return nil }
        return CGRect(x: l.maxX, y: min(l.minY, r.minY), width: r.minX - l.maxX, height: frame.maxY - min(l.minY, r.minY))
    }
}

/// The number on the menu-bar item (Settings): percent used (default), time until the reset, or
/// the reset time; or none, leaving Grandpa alone.
enum BarText: String, CaseIterable {
    case percent, timeLeft, resetClock, none

    /// The text: ✨ when a mountain is done, ? without data; while resting, the countdown until he starts again
    /// (the clock time in the reset-clock style);
    /// else the headline window (5-hour, else weekly) in the chosen style. Without a reset time,
    /// the time styles fall back to the percent.
    func text(_ s: Snapshot, cutscene: Bool, now: Date) -> String {
        if self == .none { return "" }
        if cutscene { return "✨" }
        if !s.known { return "?" }
        if s.resting { return s.wakeAt.map { self == .resetClock ? Fmt.clock($0, now: now) : Fmt.left($0, now: now) } ?? "?" }
        guard let m = s.headline else { return "" }
        switch (self, m.resetsAt) {
        case (.timeLeft, let r?): return Fmt.left(r, now: now)
        case (.resetClock, let r?): return Fmt.clock(r, now: now)
        default: return Fmt.pct(m.pct)
        }
    }

    /// Whether Grandpa is drawn, and the item's title. Never an empty item: no text means Grandpa stays.
    static func item(_ text: String, grandpa: Bool) -> (image: Bool, title: String) {
        let image = grandpa || text.isEmpty
        return (image, text.isEmpty ? "" : image ? " " + text : text)
    }

    /// The popover header's "24% · Mon 04:00": the headline and when it resets; nil without data.
    static func detail(_ s: Snapshot, now: Date) -> String? {
        guard s.known, let m = s.headline else { return nil }
        let pct = Fmt.pct(m.pct)
        return m.resetsAt.map { pct + " · " + Fmt.clock($0, now: now) } ?? pct
    }
}

/// Which floating mini window to show (Settings): only while the menu-bar item is hidden (default),
/// always, or never.
enum MiniMode: String, CaseIterable {
    case auto, always, off
    func shows(barHidden: Bool) -> Bool { self == .always || (self == .auto && barHidden) }
}
