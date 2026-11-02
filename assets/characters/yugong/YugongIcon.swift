import AppKit

// The app icon: pixel Grandpa Yugong with his A-frame carrier (지게) full of earth, digging at the
// foot of his mountain under a clear sky. Built from the same pixel scene parts as the popover.

extension YugongArt {
    static let iconGrid = 52

    /// The icon art alone: iconGrid x iconGrid pixels, square, no mask.
    static func iconPixels(t: Double) -> CGImage? {
        let n = iconGrid
        let info = SceneInfo(state: .lively, carrier: 0.85, mountainLeft: 0.8, grandson: nil, night: false)
        let (pose, k) = YugongRig.pose(.lively, t: t, night: false, stepped: true)
        guard let bg = pixelLayer(n, n, outline: false, { c in pixelBackdrop(c, info, t: t, w: n, h: n) }),
              let fig = pixelFigure(pose, k: k, fill: 0.85, grid: 40, menuBar: false, bird: true),
              let c = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        c.interpolationQuality = .none
        c.draw(bg, in: CGRect(x: 0, y: 0, width: n, height: n))
        // feet (row 37.6 of the 40-pixel figure) on the ground line, 6 rows above the bottom
        c.draw(fig, in: CGRect(x: 10, y: 6 - 2, width: 40, height: 40))
        return c.makeImage()
    }

    /// A macOS-style icon at `size` points: the pixel art on a rounded square with the standard margin.
    static func appIcon(size: CGFloat, t: Double) -> NSImage {
        let art = iconPixels(t: t)
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            guard let art, let c = NSGraphicsContext.current?.cgContext else { return false }
            let inset = r.width * 100 / 1024, body = r.insetBy(dx: inset, dy: inset)
            let shape = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: -r.width * 0.01), blur: r.width * 0.02, color: NSColor(white: 0, alpha: 0.3).cgColor)
            c.addPath(shape); c.setFillColor(NSColor.black.cgColor); c.fillPath()
            c.restoreGState()
            c.saveGState()
            c.addPath(shape); c.clip()
            // whole pixels when there is room for them; smooth scaling only for the tiny sizes
            c.interpolationQuality = r.width >= 128 ? .none : .high
            c.draw(art, in: body)
            c.restoreGState()
            return true
        }
    }
}
