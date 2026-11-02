import AppKit

// The popover scene: sky for the time of day, the mountain that erodes with cumulative tokens,
// Grandpa digging at its foot, the magpie, and the grandson (Codex) with his own basket.
// Points, y down. Both styles draw the same layout.

extension YugongArt {
    static func scene(_ style: ArtStyle, _ info: SceneInfo, t: Double, size: CGSize) -> NSImage {
        switch style {
        case .ink:
            return NSImage(size: size, flipped: true) { _ in
                guard let c = NSGraphicsContext.current?.cgContext else { return false }
                inkScene(c, info, t: t, size: size)
                return true
            }
        case .pixel:
            let cell: CGFloat = 3
            let gw = Int(size.width / cell), gh = Int(size.height / cell)
            let bg = pixelLayer(gw, gh, outline: false) { c in pixelBackdrop(c, info, t: t, w: gw, h: gh) }
            let fig = figureLayer(info, t: t, grid: 40)
            let kid = info.grandson.map { kidLayer($0, t: t, grid: 24) }
            let ground = gh - 6
            return NSImage(size: size, flipped: false) { r in
                guard let c = NSGraphicsContext.current?.cgContext else { return false }
                c.interpolationQuality = .none
                if let bg { c.draw(bg, in: r) }
                // figure: 40 cells, feet (row 37.6) on the ground line
                let fx = Int(CGFloat(gw) * 0.42), fy = ground + 2 - 38
                if let fig { c.draw(fig, in: cellRect(fx, fy, 40, 40, gh: gh, cell: cell)) }
                if let kid, let k = kid { c.draw(k, in: cellRect(gw - 27, ground + 2 - 23, 24, 24, gh: gh, cell: cell)) }
                return true
            }
        }
    }

    /// A rect in y-up point space for a y-down cell rectangle.
    private static func cellRect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, gh: Int, cell: CGFloat) -> CGRect {
        CGRect(x: CGFloat(x) * cell, y: CGFloat(gh - y - h) * cell, width: CGFloat(w) * cell, height: CGFloat(h) * cell)
    }

    static func scenePose(_ info: SceneInfo, t: Double, stepped: Bool) -> (YPose, CGFloat) {
        if let c = info.cutscene { return (YugongRig.morning(c < 0.5 ? 0 : 1), CGFloat((t * 0.7).truncatingRemainder(dividingBy: 1))) }
        return YugongRig.pose(info.state, t: t, night: info.night, stepped: stepped)
    }

    private static func figureLayer(_ info: SceneInfo, t: Double, grid: Int) -> CGImage? {
        let (p, k) = scenePose(info, t: t, stepped: true)
        return pixelFigure(p, k: k, fill: CGFloat(min(1.2, info.carrier)), grid: grid, menuBar: false, bird: true)
    }

    private static func kidLayer(_ fill: Double, t: Double, grid: Int) -> CGImage? {
        pixelLayer(grid, grid) { c in
            c.scaleBy(x: CGFloat(grid) / 100, y: CGFloat(grid) / 100)
            grandson(Pen(c: c, pixel: true, mb: true, pal: .pixel, ppu: CGFloat(grid) / 100), fill: fill, t: t, stepped: true)
        }
    }

    // MARK: - sky and mountain

    struct Sky { let top: NSColor, bottom: NSColor, far: NSColor, ground: NSColor, night: Bool }

    static func sky(_ info: SceneInfo, ink: Bool) -> Sky {
        func c(_ h: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: 1)
        }
        if info.cutscene != nil { return Sky(top: c(0xFFD98A), bottom: c(0xFFF4D6), far: c(0xE8C88A), ground: c(0xB59A6A), night: false) }
        if info.state == .resting || info.night {
            return ink ? Sky(top: c(0x2E3550), bottom: c(0x56607E), far: c(0x6E7792), ground: c(0x4B4A52), night: true)
                       : Sky(top: c(0x1D2340), bottom: c(0x3C4470), far: c(0x4E5884), ground: c(0x3B3440), night: true)
        }
        switch info.state {
        case .morning: return ink ? Sky(top: c(0xF6DDB0), bottom: c(0xFBF1DF), far: c(0xD9C3A6), ground: c(0xCDB794), night: false)
                                  : Sky(top: c(0xF9C98B), bottom: c(0xFDEBC8), far: c(0xC9A585), ground: c(0x9C7A50), night: false)
        case .straining: return ink ? Sky(top: c(0xF3D2B8), bottom: c(0xF8EADB), far: c(0xD3B9A6), ground: c(0xC9AF8E), night: false)
                                    : Sky(top: c(0xF5A97F), bottom: c(0xFBD8B3), far: c(0xC48A73), ground: c(0x93704A), night: false)
        default: return ink ? Sky(top: c(0xE4E8E4), bottom: c(0xF7F2E6), far: c(0xC6CCCB), ground: c(0xD3C3A1), night: false)
                            : Sky(top: c(0x9FD3F0), bottom: c(0xDDF1F7), far: c(0x8FB5C4), ground: c(0x8F6E45), night: false)
        }
    }

    /// Ridge of the mountain, shrinking with `left` (1 = untouched). Returns points left->right
    /// in a w x h frame with ground at `g`; the right foot shows the dug-out face.
    static func ridge(w: CGFloat, g: CGFloat, left: Double) -> [CGPoint] {
        let l = CGFloat(max(0, min(1, left)))
        let full = g * 0.9, h = g * 0.14 + (full - g * 0.14) * l
        let dug = (1 - l)                                    // how much of the foot has been carried away
        let foot = w * (0.58 - 0.08 * dug)
        let shape: [(CGFloat, CGFloat)] = [(-0.12, 0.0), (0.0, 0.42), (0.08, 0.72), (0.15, 0.93), (0.21, 1.0), (0.26, 0.9),
                                            (0.31, 0.95), (0.38, 0.7)]
        var pts = shape.map { CGPoint(x: w * $0.0, y: g - h * $0.1) }
        // the face where he digs: steeper and stepped as the work adds up
        let cutTop = g - h * (0.55 - 0.25 * dug)
        pts.append(CGPoint(x: w * 0.45 - 6 * dug, y: cutTop))
        if dug > 0.08 {
            pts.append(CGPoint(x: foot - 10, y: cutTop + 2))
            pts.append(CGPoint(x: foot - 9, y: g - h * 0.22))
            pts.append(CGPoint(x: foot - 2, y: g - h * 0.2))
        }
        pts.append(CGPoint(x: foot, y: g))
        return pts
    }

    // MARK: - ink scene

    static func inkScene(_ c: CGContext, _ info: SceneInfo, t: Double, size: CGSize) {
        let W = size.width, H = size.height, g = H - 16
        let sk = sky(info, ink: true)
        let pal = Palette.ink
        // paper sky wash
        let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [sk.top.cgColor, sk.bottom.cgColor] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: H), options: [])
        // red sun / pale moon
        if sk.night {
            c.setFillColor(NSColor(white: 1, alpha: 0.9).cgColor); c.fillEllipse(in: CGRect(x: W * 0.36, y: 12, width: 18, height: 18))
            c.setFillColor(sk.top.cgColor); c.fillEllipse(in: CGRect(x: W * 0.36 + 6, y: 9, width: 18, height: 18))
            c.setFillColor(NSColor(white: 1, alpha: 0.7).cgColor)
            for (x, y) in [(0.55, 0.1), (0.62, 0.3), (0.9, 0.12), (0.82, 0.38), (0.47, 0.22)] as [(CGFloat, CGFloat)] {
                c.fillEllipse(in: CGRect(x: W * x, y: H * y, width: 2, height: 2))
            }
        } else {
            let y: CGFloat = info.state == .morning ? 46 : 18
            c.setFillColor(pal.sash.withAlphaComponent(0.85).cgColor); c.fillEllipse(in: CGRect(x: W * 0.36, y: y, width: 24, height: 24))
        }
        // far range, a pale wash
        let far = CGMutablePath()
        far.move(to: CGPoint(x: 0, y: g))
        for i in 0...12 {
            let x = W * CGFloat(i) / 12
            far.addLine(to: CGPoint(x: x, y: g - 34 - 16 * sin(CGFloat(i) * 1.7) - 8 * cos(CGFloat(i) * 0.9)))
        }
        far.addLine(to: CGPoint(x: W, y: g)); far.closeSubpath()
        c.addPath(far); c.setFillColor(sk.far.withAlphaComponent(0.55).cgColor); c.fillPath()
        // mist band
        c.setFillColor(sk.bottom.withAlphaComponent(0.7).cgColor); c.fill(CGRect(x: 0, y: g - 22, width: W, height: 10))

        // the mountain
        let pts = ridge(w: W, g: g, left: info.mountainLeft)
        let lift: CGFloat = info.cutscene.map { CGFloat(min(1, max(0, ($0 - 0.15) / 0.7))) * (g + 40) } ?? 0
        c.saveGState()
        c.translateBy(x: 0, y: -lift)
        let m = CGMutablePath(); m.addLines(between: pts); m.closeSubpath()
        c.saveGState(); c.addPath(m); c.clip()
        let mg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
            pal.outline.withAlphaComponent(sk.night ? 0.8 : 0.62).cgColor, pal.outline.withAlphaComponent(0.12).cgColor,
            sk.bottom.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 0.55, 1])!
        let top = pts.map(\.y).min() ?? 0
        c.drawLinearGradient(mg, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: g), options: [])
        // dry-brush texture strokes (cun)
        let pen = Pen(c: c, pixel: false, mb: false, pal: pal, ppu: 1)
        for i in 0..<9 {
            let x = W * (0.04 + 0.05 * CGFloat(i)), y0 = top + 12 + CGFloat((i * 37) % 23)
            pen.brush([CGPoint(x: x, y: y0), CGPoint(x: x + 5, y: y0 + 9), CGPoint(x: x + 3, y: y0 + 18)], 1.3, pal.outline.withAlphaComponent(0.35))
        }
        c.restoreGState()
        // ridge line in one confident stroke
        pen.brush(Array(pts.dropFirst().prefix(8)), 2.6, pal.outline.withAlphaComponent(0.85))
        // pines on the slopes
        for f in [0.1, 0.17, 0.27, 0.33] as [CGFloat] {
            let x = W * f
            guard let y = ridgeY(pts, x) else { continue }
            pen.brush([CGPoint(x: x, y: y - 9), CGPoint(x: x, y: y + 1)], 1.2)
            for j in 0..<3 { let yy = y - 8 + CGFloat(j) * 3; pen.brush([CGPoint(x: x - 4 + CGFloat(j), y: yy + 1), CGPoint(x: x + 4 - CGFloat(j), y: yy)], 1.4) }
        }
        if info.cutscene != nil {   // clouds carrying the mountain away
            c.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
            for i in 0..<6 { c.fillEllipse(in: CGRect(x: W * CGFloat(i) / 6 - 10, y: g - 14 + CGFloat(i % 2) * 4, width: 70, height: 24)) }
        }
        c.restoreGState()

        // ground and a heap of carried earth where he works
        c.setFillColor(sk.ground.cgColor)
        let gp = CGMutablePath(); gp.move(to: CGPoint(x: 0, y: g)); gp.addQuadCurve(to: CGPoint(x: W, y: g - 2), control: CGPoint(x: W / 2, y: g - 6))
        gp.addLine(to: CGPoint(x: W, y: H)); gp.addLine(to: CGPoint(x: 0, y: H)); gp.closeSubpath()
        c.addPath(gp); c.fillPath()
        pen.brush([CGPoint(x: 0, y: g), CGPoint(x: W * 0.5, y: g - 4), CGPoint(x: W, y: g - 2)], 1.6, pal.outline.withAlphaComponent(0.6))

        // grandson (Codex) and Grandpa
        if let fill = info.grandson {
            let s: CGFloat = 70
            c.saveGState(); c.translateBy(x: W - s - 4, y: g + 3 - s * 0.94); c.scaleBy(x: s / 100, y: s / 100)
            grandson(Pen(c: c, pixel: false, mb: false, pal: pal, ppu: s / 100), fill: fill, t: t, stepped: false)
            c.restoreGState()
        }
        let (p, k) = scenePose(info, t: t, stepped: false)
        let s: CGFloat = 124
        c.saveGState(); c.translateBy(x: W * 0.4, y: g + 4 - s * 0.94); c.scaleBy(x: s / 100, y: s / 100)
        draw(Pen(c: c, pixel: false, mb: false, pal: pal, ppu: s / 100), p, k: k, fill: CGFloat(min(1.2, info.carrier)), bird: true)
        c.restoreGState()

        // red seal, bottom left: the ink style's signature
        c.setFillColor(pal.sash.cgColor)
        let seal = CGRect(x: 10, y: H - 26, width: 16, height: 16)
        c.addPath(CGPath(roundedRect: seal, cornerWidth: 2, cornerHeight: 2, transform: nil)); c.fillPath()
        c.setStrokeColor(NSColor(white: 1, alpha: 0.9).cgColor); c.setLineWidth(1.4)
        c.addPath(pen.path([CGPoint(x: 14, y: H - 21), CGPoint(x: 22, y: H - 21)])); c.strokePath()
        c.addPath(pen.path([CGPoint(x: 18, y: H - 23.5), CGPoint(x: 18, y: H - 13)])); c.strokePath()
        c.addPath(pen.path([CGPoint(x: 14, y: H - 15), CGPoint(x: 22, y: H - 15)])); c.strokePath()
    }

    static func ridgeY(_ pts: [CGPoint], _ x: CGFloat) -> CGFloat? {
        for i in 0..<(pts.count - 1) where pts[i].x <= x && pts[i + 1].x >= x {
            let u = (x - pts[i].x) / max(0.001, pts[i + 1].x - pts[i].x)
            return pts[i].y + (pts[i + 1].y - pts[i].y) * u
        }
        return nil
    }

    // MARK: - pixel backdrop (drawn in cells)

    static func pixelBackdrop(_ c: CGContext, _ info: SceneInfo, t: Double, w: Int, h: Int) {
        let sk = sky(info, ink: false)
        let W = CGFloat(w), H = CGFloat(h), g = H - 6
        // dithered sky: two colours, ordered 2x2 dither in the middle band
        for y in 0..<h {
            let u = CGFloat(y) / H
            for x in 0..<w {
                let thr: CGFloat = [0.2, 0.6, 0.8, 0.4][(x % 2) + (y % 2) * 2]
                c.setFillColor((u * 1.6 - 0.3 > thr ? sk.bottom : sk.top).cgColor)
                c.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        if sk.night {
            c.setFillColor(NSColor.white.cgColor)
            for (x, y) in [(0.55, 0.1), (0.62, 0.3), (0.9, 0.12), (0.82, 0.38), (0.47, 0.22), (0.7, 0.05)] as [(CGFloat, CGFloat)] {
                c.fill(CGRect(x: floor(W * x), y: floor(H * y), width: 1, height: 1))
            }
            c.setFillColor(NSColor(srgbRed: 1, green: 0.96, blue: 0.8, alpha: 1).cgColor)
            let mx = floor(W * 0.38)
            for (x, y, w) in [(2, 0, 2), (1, 1, 2), (0, 2, 2), (0, 3, 2), (0, 4, 2), (1, 5, 2), (2, 6, 2)] as [(CGFloat, CGFloat, CGFloat)] {
                c.fill(CGRect(x: mx + x, y: 3 + y, width: w, height: 1))
            }
        } else {
            c.setFillColor(NSColor(srgbRed: 1, green: 0.85, blue: 0.4, alpha: 1).cgColor)
            c.fillEllipse(in: CGRect(x: floor(W * 0.36), y: info.state == .morning ? 14 : 4, width: 8, height: 8))
        }
        // far hills
        c.setFillColor(sk.far.cgColor)
        for x in 0..<w {
            let y = g - 10 - 4 * sin(CGFloat(x) * 0.17) - 2 * cos(CGFloat(x) * 0.41)
            c.fill(CGRect(x: CGFloat(x), y: floor(y), width: 1, height: g - floor(y)))
        }
        // the mountain in stepped pixels with a lit and a shaded face
        let lift: CGFloat = info.cutscene.map { CGFloat(min(1, max(0, ($0 - 0.15) / 0.7))) * (g + 14) } ?? 0
        let pts = ridge(w: W, g: g, left: info.mountainLeft).map { CGPoint(x: $0.x, y: $0.y - lift) }
        let peakX = pts.min(by: { $0.y < $1.y })?.x ?? W * 0.2
        let rock = sk.night ? NSColor(srgbRed: 0.24, green: 0.30, blue: 0.36, alpha: 1) : NSColor(srgbRed: 0.42, green: 0.60, blue: 0.42, alpha: 1)
        let shade = sk.night ? NSColor(srgbRed: 0.17, green: 0.21, blue: 0.27, alpha: 1) : NSColor(srgbRed: 0.30, green: 0.46, blue: 0.34, alpha: 1)
        let edge = NSColor(srgbRed: 0.16, green: 0.2, blue: 0.18, alpha: 1)
        for x in 0..<w {
            guard let top = ridgeY(pts, CGFloat(x) + 0.5) else { continue }
            let ty = floor(top), by = g - lift
            guard by > ty else { continue }
            let shaded = CGFloat(x) > peakX + 2 || (CGFloat(x) > peakX - 2 && (x + Int(ty)) % 2 == 0)
            c.setFillColor((shaded ? shade : rock).cgColor); c.fill(CGRect(x: CGFloat(x), y: ty, width: 1, height: by - ty))
            c.setFillColor(edge.cgColor); c.fill(CGRect(x: CGFloat(x), y: ty, width: 1, height: 1))
        }
        // pines and dug ledges
        c.setFillColor(edge.cgColor)
        for f in [0.1, 0.17, 0.27, 0.33] as [CGFloat] {
            let x = floor(W * f)
            guard let y = ridgeY(pts, x) else { continue }
            let yy = floor(y) + 2
            c.fill(CGRect(x: x, y: yy - 3, width: 1, height: 4)); c.fill(CGRect(x: x - 1, y: yy - 2, width: 3, height: 2))
        }
        if info.cutscene != nil {
            c.setFillColor(NSColor.white.cgColor)
            for i in 0..<7 { c.fillEllipse(in: CGRect(x: CGFloat(i) * W / 7 - 3, y: g - lift - 4 + CGFloat(i % 2) * 2, width: 20, height: 7)) }
        }
        // ground
        c.setFillColor(sk.ground.cgColor); c.fill(CGRect(x: 0, y: g, width: W, height: H - g))
        c.setFillColor(edge.withAlphaComponent(1).cgColor); c.fill(CGRect(x: 0, y: g, width: W, height: 1))
        c.setFillColor(NSColor(srgbRed: 0.45, green: 0.62, blue: 0.35, alpha: 1).cgColor)
        for x in stride(from: 3, to: w, by: 7) { c.fill(CGRect(x: CGFloat(x), y: g - 1, width: 1, height: 1)) }
    }

    // MARK: - the grandson (Codex)

    /// A small boy with a topknot tuft carrying his own basket; its earth is the Codex meter.
    static func grandson(_ pn: Pen, fill: Double, t: Double, stepped: Bool) {
        let pal = pn.pal
        let tired = fill >= 1
        var ph = t * 2.2
        if stepped { ph = floor(ph * 2) / 2 }
        let stepA = CGFloat(sin(ph * .pi)), bob = tired ? 0 : abs(stepA) * 2
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y - bob) }
        let edge = !pn.pixel
        // basket on his back with earth
        let rimA = P(57, 44), rimB = P(80, 42)
        if fill > 0.03 {
            let m = CGMutablePath(); m.move(to: rimA)
            m.addQuadCurve(to: rimB, control: P(68, 42 - 26 * CGFloat(min(1.1, fill)))); m.closeSubpath()
            pn.shape(m, pal.earth, edge: edge)
        }
        pn.shape(pn.path([rimA, rimB, P(77, 70), P(60, 72)], closed: true), pal.hat, edge: edge)
        if tired {
            // sits on the ground, legs out
            pn.tube([P(48, 80), P(30, 88)], 9, pal.pants, edge: edge)
        } else {
            pn.tube([P(52, 76), P(50 - 6 * stepA, 92)], 9, pal.pantsDark, edge: edge)
            pn.tube([P(48, 76), P(46 + 6 * stepA, 92)], 9, pal.pants, edge: edge)
        }
        pn.shape(pn.path([P(38, 52), P(60, 50), P(62, 80), P(36, 80)], closed: true), pal.kid, edge: edge)
        pn.tube([P(40, 58), P(36, 70)], 7, pal.kid, edge: edge)
        pn.ellipse(P(36, 72), 6, 6, pal.skin, edge: edge)
        // big round head, black hair cap with a tuft
        pn.ellipse(P(48, 34), 30, 28, pal.skin, edge: edge)
        let hair = CGMutablePath()
        hair.move(to: P(33, 32)); hair.addCurve(to: P(63, 32), control1: P(34, 14), control2: P(62, 14))
        hair.addQuadCurve(to: P(46, 26), control: P(55, 26)); hair.addQuadCurve(to: P(33, 32), control: P(38, 25)); hair.closeSubpath()
        pn.shape(hair, pal.kidHair, edge: edge)
        pn.ellipse(P(50, 15), 9, 8, pal.kidHair, edge: edge)
        pn.ellipse(P(57, 39), 6, 3.4, pal.blush, edge: false)
        if tired {
            pn.brush([P(40, 37), P(43, 38.5), P(46, 37)], pn.pixel ? 1 : 1.4)
        } else {
            pn.dot(P(41, 36), pn.pixel ? 0 : 2.2, pixels: 1)
            pn.dot(P(52, 36), pn.pixel ? 0 : 2.2, pixels: 1)
        }
        pn.brush([P(42, 43), P(45, 45), P(48, 43)], pn.pixel ? 1 : 1.3)
    }
}
