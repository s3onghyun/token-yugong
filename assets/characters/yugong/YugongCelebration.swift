import AppKit

// A new title: the magpie (까치, the bird of good news) chirps it, and pixel confetti falls.
// Both are drawn on small pixel grids without anti-aliasing, like the rest of the cast.

enum Celebration {
    static let colors: [NSColor] = ([0xE0B040, 0xC9483A, 0x3E6FC9, 0x4DB884, 0xF4EEE0, 0xD9965F] as [UInt32]).map { (h: UInt32) -> NSColor in
        let r = CGFloat((h >> 16) & 0xFF), g = CGFloat((h >> 8) & 0xFF), b = CGFloat(h & 0xFF)
        return NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    /// The magpie alone, facing right, beak opening and closing (`t` in seconds).
    static func magpie(size: CGFloat, t: Double) -> NSImage {
        var rows = PixelHeads.bird.map { Array($0) }
        if Int(t * 6) % 2 == 0 { rows[1][0] = "o"; rows[2][0] = "." }   // beak open
        let w = rows[0].count + 2, h = rows.count + 2
        let cg = YugongArt.pixelLayer(w, h, outline: false, { c in PixelHeads.stampRows(c, rows, ox: 1, oy: 1, mirror: true) })
        return YugongArt.crisp(cg, size: NSSize(width: size, height: size * CGFloat(h) / CGFloat(w)))
    }

    /// Confetti falling through a `size` area, one pixel per 3 points; the same `t` draws the same picture.
    static func confetti(t: Double, size: CGSize) -> NSImage {
        let w = max(1, Int(size.width / 3)), h = max(1, Int(size.height / 3))
        let cg = YugongArt.pixelLayer(w, h, outline: false, { c in
            for i in 0..<48 {
                var g = UInt64(i + 1) &* 0x9E37_79B9_7F4A_7C15   // a fixed scatter per piece
                func next() -> Double { g ^= g >> 12; g ^= g << 25; g ^= g >> 27; return Double((g &* 0x2545_F491_4F6C_DD1D) >> 11) / Double(1 << 53) }
                let x0 = next() * Double(w), speed = 6 + next() * 10, phase = next() * Double(h + 4)
                let y = (phase + t * speed).truncatingRemainder(dividingBy: Double(h + 4)) - 2
                let x = x0 + sin(t * 2 + Double(i)) * 1.5
                c.setFillColor(colors[i % colors.count].cgColor)
                // a piece flutters: wide, then narrow
                let flat = Int(t * 4 + Double(i)) % 2 == 0
                c.fill(CGRect(x: Int(x), y: Int(y), width: flat ? 2 : 1, height: flat ? 1 : 2))
            }
        })
        return YugongArt.crisp(cg, size: size)
    }
}

extension TokenPetAssets {
    /// The magpie announcing good news, `size` points wide.
    public static func magpie(size: CGFloat, t: Double) -> NSImage { Celebration.magpie(size: size, t: t) }
    /// Pixel confetti over a `size` area at time `t` (seconds).
    public static func confetti(t: Double, size: CGSize) -> NSImage { Celebration.confetti(t: t, size: size) }
}
