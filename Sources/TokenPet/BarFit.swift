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

    /// The notch strip from NSScreen's auxiliary areas (macOS 12+): the gap between the usable
    /// menu-bar areas left and right of the camera.
    static func notch(frame: CGRect, left: CGRect?, right: CGRect?) -> CGRect? {
        guard let l = left, let r = right, r.minX > l.maxX else { return nil }
        return CGRect(x: l.maxX, y: min(l.minY, r.minY), width: r.minX - l.maxX, height: frame.maxY - min(l.minY, r.minY))
    }
}

/// Which floating mini window to show (Settings): only while the menu-bar item is hidden (default),
/// always, or never.
enum MiniMode: String, CaseIterable {
    case auto, always, off
    func shows(barHidden: Bool) -> Bool { self == .always || (self == .auto && barHidden) }
}
