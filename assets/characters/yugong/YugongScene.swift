import AppKit

// The popover scene: sky for the time of day, the mountain that erodes with cumulative tokens,
// Grandpa digging at its foot, the magpie, and the grandson (Codex) with his own basket.
// Drawn in 3-point cells.

extension YugongArt {
    static func scene(_ info: SceneInfo, t: Double, size: CGSize) -> NSImage {
        let cell: CGFloat = 3
        let gw = Int(size.width / cell), gh = Int(size.height / cell)
        let bg = pixelLayer(gw, gh, outline: false) { c in pixelBackdrop(c, info, t: t, w: gw, h: gh) }
        let fig = figureLayer(info, t: t, grid: 40)
        let kid = info.grandson.map { kidLayer($0, t: t, grid: 24) }
        let son = info.son.map { sonLayer(sonPose(t, fill: $0), fill: $0) }
        let boy = info.boy.map { boyLayer(boyPose(t, fill: $0), fill: $0) }
        let guest = info.cutscene == nil ? info.visitor.map { visitorLayer($0, t: t) } : nil
        let glint = info.sparkle.flatMap { n in pixelLayer(gw, gh, outline: false) { c in TitleWorld.sparkle(c, n, info, t: t, w: gw, h: gh) } }
        let ground = gh - 6
        return NSImage(size: size, flipped: false) { r in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            c.interpolationQuality = .none
            if let bg { c.draw(bg, in: r) }
            // the son at the mountain's foot and the boy in front of it, both behind Grandpa
            if let son, let s = son { c.draw(s, in: cellRect(12, ground + 2 - 30, 32, 32, gh: gh, cell: cell)) }
            if let boy, let b = boy { c.draw(b, in: cellRect(-3, ground + 2 - 21, 22, 22, gh: gh, cell: cell)) }
            // figure: 40 cells, feet (row 37.6) on the ground line
            let fx = Int(CGFloat(gw) * 0.42), fy = ground + 2 - 38
            if let fig { c.draw(fig, in: cellRect(fx, fy, 40, 40, gh: gh, cell: cell)) }
            if let kid, let k = kid { c.draw(k, in: cellRect(gw - 27, ground + 2 - 23, 24, 24, gh: gh, cell: cell)) }
            if let (img, n) = guest, let g = img { c.draw(g, in: cellRect(0, ground + 2 - n, n, n, gh: gh, cell: cell)) }
            if let glint { c.draw(glint, in: r) }
            return true
        }
    }

    /// A rect in y-up point space for a y-down cell rectangle.
    private static func cellRect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, gh: Int, cell: CGFloat) -> CGRect {
        CGRect(x: CGFloat(x) * cell, y: CGFloat(gh - y - h) * cell, width: CGFloat(w) * cell, height: CGFloat(h) * cell)
    }

    static func scenePose(_ info: SceneInfo, t: Double) -> (YPose, CGFloat) {
        if let c = info.cutscene { return (YugongRig.morning(c < 0.5 ? 0 : 1), CGFloat((t * 0.7).truncatingRemainder(dividingBy: 1))) }
        return YugongRig.pose(info.state, t: t, night: info.night, tempo: info.tempo)
    }

    private static func figureLayer(_ info: SceneInfo, t: Double, grid: Int) -> CGImage? {
        let (p, k) = scenePose(info, t: t)
        return pixelFigure(p, k: k, fill: CGFloat(min(1.2, info.carrier)), grid: grid, menuBar: false, bird: true, titles: info.titles)
    }

    private static func kidLayer(_ fill: Double, t: Double, grid: Int) -> CGImage? {
        pixelLayer(grid, grid) { c in
            c.scaleBy(x: CGFloat(grid) / 100, y: CGFloat(grid) / 100)
            grandson(Pen(c: c, mb: true, pal: .pixel, ppu: CGFloat(grid) / 100), fill: fill, t: t)
        }
    }

    // MARK: - sky and mountain

    struct Sky { let top: NSColor, bottom: NSColor, far: NSColor, ground: NSColor, night: Bool }

    static func sky(_ info: SceneInfo) -> Sky {
        func c(_ h: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: 1)
        }
        if info.cutscene != nil { return Sky(top: c(0xFFD98A), bottom: c(0xFFF4D6), far: c(0xE8C88A), ground: c(0xB59A6A), night: false) }
        if info.state == .resting || info.night {
            return Sky(top: c(0x1D2340), bottom: c(0x3C4470), far: c(0x4E5884), ground: c(0x3B3440), night: true)
        }
        switch info.state {
        case .morning: return Sky(top: c(0xF9C98B), bottom: c(0xFDEBC8), far: c(0xC9A585), ground: c(0x9C7A50), night: false)
        case .straining: return Sky(top: c(0xF5A97F), bottom: c(0xFBD8B3), far: c(0xC48A73), ground: c(0x93704A), night: false)
        default: return Sky(top: c(0x9FD3F0), bottom: c(0xDDF1F7), far: c(0x8FB5C4), ground: c(0x8F6E45), night: false)
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

    static func ridgeY(_ pts: [CGPoint], _ x: CGFloat) -> CGFloat? {
        for i in 0..<(pts.count - 1) where pts[i].x <= x && pts[i + 1].x >= x {
            let u = (x - pts[i].x) / max(0.001, pts[i + 1].x - pts[i].x)
            return pts[i].y + (pts[i + 1].y - pts[i].y) * u
        }
        return nil
    }

    // MARK: - pixel backdrop (drawn in cells)

    static func pixelBackdrop(_ c: CGContext, _ info: SceneInfo, t: Double, w: Int, h: Int) {
        let sk = sky(info)
        let W = CGFloat(w), H = CGFloat(h), g = H - 6
        let props = info.props, lay = TitleWorld.layout(info, w: w)
        let edge = NSColor(srgbRed: 0.16, green: 0.2, blue: 0.18, alpha: 1)
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
        if props { TitleWorld.horizon(c, info, lay, w: W, g: g, night: sk.night) }
        // the mountain in stepped pixels with a lit and a shaded face
        let move = info.cutscene.map { cutsceneMotion($0, width: w) }
        let lift = move?.lift ?? 0, dx = move?.dx ?? 0
        // in the cutscene what is left is drawn at least 30% high, so the sons have a mountain to carry
        let left = info.cutscene == nil ? info.mountainLeft : info.finale ? 0.55 : max(0.3, info.mountainLeft)
        let pts = ridge(w: W, g: g, left: left).map { CGPoint(x: $0.x + dx, y: $0.y - lift) }
        if let move {
            // Kua'e's two sons, behind the mountain: they rise out of the earth holding it up, then carry it off.
            // The finale: one takes this mountain west, the other a second one (Wangwu, at the right) east.
            let sons: [(Int, CGFloat, Bool)] = info.finale ? [(0, 0.2, false), (1, 0.8, true)] : [(0, 0.12, false), (1, 0.38, false)]
            for (b, cx, east) in sons {
                let img = giantLayer(move.pose, brother: b)
                let r = CGRect(x: floor(W * cx) - 18 + (east ? -dx : dx), y: g - lift - 2, width: 36, height: 36)
                c.saveGState(); c.translateBy(x: east ? r.minX + r.maxX : 0, y: r.minY + r.maxY); c.scaleBy(x: east ? -1 : 1, y: -1)   // the layer is y-up
                if let img { c.draw(img, in: r) }
                c.restoreGState()
            }
        }
        if info.finale {   // the second mountain: the same ridge, mirrored and a little lower, carried the other way
            let east = ridge(w: W, g: g, left: 0.4).reversed().map { CGPoint(x: W - $0.x - dx, y: $0.y - lift) }
            drawMountain(c, east, w: w, g: g, lift: lift, dx: -dx, night: sk.night, mirror: true)
        }
        drawMountain(c, pts, w: w, g: g, lift: lift, dx: dx, night: sk.night)
        if props { TitleWorld.mountain(c, info, pts, w: W, g: g, night: sk.night); TitleWorld.sky(c, info, w: W, night: sk.night) }
        if let cs = info.cutscene, cs > 0.05, cs < 0.45 {   // dust as the earth gives up the mountain
            c.setFillColor(NSColor.white.cgColor)
            for i in 0..<4 { c.fillEllipse(in: CGRect(x: CGFloat(i) * W / 7 - 3, y: g - 4 + CGFloat(i % 2) * 2, width: 20, height: 7)) }
        }
        // ground
        c.setFillColor(sk.ground.cgColor); c.fill(CGRect(x: 0, y: g, width: W, height: H - g))
        c.setFillColor(edge.withAlphaComponent(1).cgColor); c.fill(CGRect(x: 0, y: g, width: W, height: 1))
        c.setFillColor(NSColor(srgbRed: 0.45, green: 0.62, blue: 0.35, alpha: 1).cgColor)
        for x in stride(from: 3, to: w, by: 7) { c.fill(CGRect(x: CGFloat(x), y: g - 1, width: 1, height: 1)) }
        if props { TitleWorld.ground(c, info, lay, w: W, g: g, night: sk.night) }
    }

    /// One mountain from its ridge, lit and shaded, with pines (moved by `dx`, lifted by `lift`).
    static func drawMountain(_ c: CGContext, _ pts: [CGPoint], w: Int, g: CGFloat, lift: CGFloat, dx: CGFloat, night: Bool, mirror: Bool = false) {
        let W = CGFloat(w)
        let peakX = pts.min(by: { $0.y < $1.y })?.x ?? W * 0.2
        let rock = night ? NSColor(srgbRed: 0.24, green: 0.30, blue: 0.36, alpha: 1) : NSColor(srgbRed: 0.42, green: 0.60, blue: 0.42, alpha: 1)
        let shade = night ? NSColor(srgbRed: 0.17, green: 0.21, blue: 0.27, alpha: 1) : NSColor(srgbRed: 0.30, green: 0.46, blue: 0.34, alpha: 1)
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
            let x = (mirror ? W - floor(W * f) : floor(W * f)) + dx
            guard let y = ridgeY(pts, x) else { continue }
            let yy = floor(y) + 2
            c.fill(CGRect(x: x, y: yy - 3, width: 1, height: 4)); c.fill(CGRect(x: x - 1, y: yy - 2, width: 3, height: 2))
        }
    }

    // MARK: - the grandson (Codex)

    /// A small boy with a topknot tuft carrying his own basket; its earth is the Codex meter.
    static func grandson(_ pn: Pen, fill: Double, t: Double) {
        let pal = pn.pal
        let tired = fill >= 1
        let ph = floor(t * 2.2 * 2) / 2
        let stepA = CGFloat(sin(ph * .pi)), bob = tired ? 0 : abs(stepA) * 2
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y - bob) }
        // basket on his back with earth
        let rimA = P(57, 44), rimB = P(80, 42)
        if fill > 0.03 {
            let m = CGMutablePath(); m.move(to: rimA)
            m.addQuadCurve(to: rimB, control: P(68, 42 - 26 * CGFloat(min(1.1, fill)))); m.closeSubpath()
            pn.shape(m, pal.earth, edge: false)
        }
        pn.shape(pn.path([rimA, rimB, P(77, 70), P(60, 72)], closed: true), pal.hat, edge: false)
        if tired {
            // sits on the ground, legs out
            pn.tube([P(48, 80), P(30, 88)], 9, pal.pants, edge: false)
        } else {
            pn.tube([P(52, 76), P(50 - 6 * stepA, 92)], 9, pal.pantsDark, edge: false)
            pn.tube([P(48, 76), P(46 + 6 * stepA, 92)], 9, pal.pants, edge: false)
        }
        pn.shape(pn.path([P(38, 52), P(60, 50), P(62, 80), P(36, 80)], closed: true), pal.kid, edge: false)
        pn.tube([P(40, 58), P(36, 70)], 7, pal.kid, edge: false)
        pn.ellipse(P(36, 72), 6, 6, pal.skin, edge: false)
        // big round head, black hair cap with a tuft
        pn.ellipse(P(48, 34), 30, 28, pal.skin, edge: false)
        let hair = CGMutablePath()
        hair.move(to: P(33, 32)); hair.addCurve(to: P(63, 32), control1: P(34, 14), control2: P(62, 14))
        hair.addQuadCurve(to: P(46, 26), control: P(55, 26)); hair.addQuadCurve(to: P(33, 32), control: P(38, 25)); hair.closeSubpath()
        pn.shape(hair, pal.kidHair, edge: false)
        pn.ellipse(P(50, 15), 9, 8, pal.kidHair, edge: false)
        pn.ellipse(P(57, 39), 6, 3.4, pal.blush, edge: false)
        if tired {
            pn.line([P(40, 37), P(43, 38.5), P(46, 37)])
        } else {
            pn.dot(P(41, 36))
            pn.dot(P(52, 36))
        }
        pn.line([P(42, 43), P(45, 45), P(48, 43)])
    }
}
