import AppKit

// Grandpa Yugong, drawn twice from the same rig (YugongRig):
//   .pixel - flat limited palette, no anti-aliasing, 1-pixel outline, whole-cell scaling
//   .ink   - clean vector with sumi-ink outlines, soft washes and tapered brush accents
// Everything here is original drawing code written for this project (see assets/PROVENANCE.md).

private func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

struct Palette {
    let outline, skin, nose, beard, beardShade, hat, hatDark, band, jacket, jacketLight, jacketDark, sash, pants, pantsDark: NSColor
    let wood, woodDark, earth, earthDark, iron, ironDark, blush, sweat, bird, birdWhite, birdBlue, mouth, kid, kidHair: NSColor

    static let pixel = Palette(
        outline: rgb(0x2B1D16), skin: rgb(0xF3C8A0), nose: rgb(0xE88F78), beard: rgb(0xFDFBF4), beardShade: rgb(0xD3CEC2),
        hat: rgb(0xEBBE5E), hatDark: rgb(0xB8873A), band: rgb(0x8A5A2B), jacket: rgb(0x4A6B9E), jacketLight: rgb(0x6A8CC2), jacketDark: rgb(0x334C75),
        sash: rgb(0xC9483A), pants: rgb(0xEFE7D6), pantsDark: rgb(0xC9BFA9),
        wood: rgb(0x9C6538), woodDark: rgb(0x6B4223), earth: rgb(0x8E6B45), earthDark: rgb(0x664A2D),
        iron: rgb(0xB2BBC2), ironDark: rgb(0x77818B), blush: rgb(0xF59C8C), sweat: rgb(0x8FD3FF),
        bird: rgb(0x1F2433), birdWhite: rgb(0xFFFFFF), birdBlue: rgb(0x4A6FD1), mouth: rgb(0x8C2F2A),
        kid: rgb(0xE0683F), kidHair: rgb(0x2B1D16))

    static let ink = Palette(
        outline: rgb(0x26211D), skin: rgb(0xF4DCC2), nose: rgb(0xEBA898), beard: rgb(0xFFFFFF), beardShade: rgb(0xE4E0D6),
        hat: rgb(0xE6C784), hatDark: rgb(0xC09A55), band: rgb(0x7E5A36), jacket: rgb(0x8396B6), jacketLight: rgb(0x9AAAC6), jacketDark: rgb(0x61739A),
        sash: rgb(0xC0473A), pants: rgb(0xF4EFE4), pantsDark: rgb(0xD9D1C1),
        wood: rgb(0xA57D53), woodDark: rgb(0x7A5838), earth: rgb(0xA08566), earthDark: rgb(0x7D6449),
        iron: rgb(0xC5CBD0), ironDark: rgb(0x8E969D), blush: rgb(0xF2A79A, 0.75), sweat: rgb(0x9BD2F2),
        bird: rgb(0x26211D), birdWhite: rgb(0xFFFFFF), birdBlue: rgb(0x5A78C8), mouth: rgb(0x9A3B33),
        kid: rgb(0xD9714C), kidHair: rgb(0x26211D))
}

/// Drawing surface shared by both styles. Coordinates are figure units (0...100, y down).
struct Pen {
    let c: CGContext
    let pixel: Bool
    let mb: Bool
    let pal: Palette
    /// device pixels per unit (pixel style), used to express widths in whole pixels
    var ppu: CGFloat
    /// > 1 inside a scaled sub-drawing (the head), so outlines keep their width
    var olScale: CGFloat = 1

    var ol: CGFloat { pixel ? px(1) : (mb ? 4.2 : 1.7) / olScale }
    func px(_ n: CGFloat) -> CGFloat { n / ppu }

    func path(_ pts: [CGPoint], closed: Bool = false) -> CGPath {
        let p = CGMutablePath()
        guard let f = pts.first else { return p }
        p.move(to: f)
        for q in pts.dropFirst() { p.addLine(to: q) }
        if closed { p.closeSubpath() }
        return p
    }

    /// Fill a closed shape and give it an outline (ink) or an inner edge (pixel, large sizes only).
    func shape(_ p: CGPath, _ col: NSColor, edge: Bool = true) {
        c.addPath(p); c.setFillColor(col.cgColor); c.fillPath()
        guard edge, !(pixel && mb) else { return }
        c.addPath(p); c.setStrokeColor(pal.outline.cgColor); c.setLineWidth(ol); c.setLineJoin(.round); c.strokePath()
    }

    func ellipse(_ ctr: CGPoint, _ w: CGFloat, _ h: CGFloat, _ col: NSColor, edge: Bool = true, rot: CGFloat = 0) {
        var tf = CGAffineTransform(translationX: ctr.x, y: ctr.y).rotated(by: rot)
        let p = CGPath(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), transform: &tf)
        shape(p, col, edge: edge)
    }

    /// A limb or pole: a thick line with an outline around it.
    func tube(_ pts: [CGPoint], _ w: CGFloat, _ col: NSColor, edge: Bool = true) {
        let p = path(pts)
        c.setLineCap(.round); c.setLineJoin(.round)
        if edge && !(pixel && mb) {
            c.addPath(p); c.setStrokeColor(pal.outline.cgColor); c.setLineWidth(w + ol * 2); c.strokePath()
        }
        c.addPath(p); c.setStrokeColor(col.cgColor); c.setLineWidth(w); c.strokePath()
    }

    /// Tapered brush stroke (ink); a plain thin line in pixel art.
    func brush(_ pts: [CGPoint], _ w: CGFloat, _ col: NSColor? = nil) {
        let col = col ?? pal.outline
        guard pts.count >= 2 else { return }
        if pixel {
            c.setLineCap(.square); c.addPath(path(pts)); c.setStrokeColor(col.cgColor); c.setLineWidth(px(1)); c.strokePath()
            return
        }
        // sample a Catmull-Rom curve and offset both sides by a swelling width
        var s: [CGPoint] = []
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(pts.count - 1, i + 2)]
            for j in 0..<8 {
                let t = CGFloat(j) / 8, t2 = t * t, t3 = t2 * t
                func cr(_ a: CGFloat, _ b: CGFloat, _ cc: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * (2 * b + (-a + cc) * t + (2 * a - 5 * b + 4 * cc - d) * t2 + (-a + 3 * b - 3 * cc + d) * t3)
                }
                s.append(CGPoint(x: cr(p0.x, p1.x, p2.x, p3.x), y: cr(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        s.append(pts.last!)
        var left: [CGPoint] = [], right: [CGPoint] = []
        for (i, q) in s.enumerated() {
            let a = s[max(0, i - 1)], b = s[min(s.count - 1, i + 1)]
            var nx = -(b.y - a.y), ny = b.x - a.x
            let len = max(0.0001, (nx * nx + ny * ny).squareRoot()); nx /= len; ny /= len
            let u = CGFloat(i) / CGFloat(s.count - 1)
            let hw = w * 0.5 * (0.25 + 0.75 * sin(.pi * min(1, u * 1.15)))   // press in, lift off
            left.append(CGPoint(x: q.x + nx * hw, y: q.y + ny * hw))
            right.append(CGPoint(x: q.x - nx * hw, y: q.y - ny * hw))
        }
        c.addPath(path(left + right.reversed(), closed: true)); c.setFillColor(col.cgColor); c.fillPath()
    }

    /// One crisp dot: a single pixel in pixel art, a small round dot in ink.
    func dot(_ p: CGPoint, _ r: CGFloat, _ col: NSColor? = nil, pixels: CGFloat = 1) {
        let col = col ?? pal.outline
        c.setFillColor(col.cgColor)
        if pixel {
            let x = floor(p.x * ppu) / ppu, y = floor(p.y * ppu) / ppu
            c.fill(CGRect(x: x, y: y, width: px(pixels), height: px(pixels)))
        } else {
            c.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
    }
}

private func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
private func sub(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
private func mul(_ a: CGPoint, _ k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
private func len(_ a: CGPoint) -> CGFloat { (a.x * a.x + a.y * a.y).squareRoot() }
/// Rotation used by the rig: + angle tips "up" toward the left (a forward lean).
private func rot(_ v: CGPoint, _ deg: CGFloat) -> CGPoint {
    let a = deg * .pi / 180
    return CGPoint(x: v.x * cos(a) + v.y * sin(a), y: -v.x * sin(a) + v.y * cos(a))
}

/// Two-bone reach: returns the joint, bending toward `pref`.
private func joint(_ root: CGPoint, _ target: CGPoint, _ a: CGFloat, _ b: CGFloat, pref: CGPoint) -> (CGPoint, CGPoint) {
    var d = sub(target, root)
    var dl = len(d)
    let maxL = a + b - 0.01
    var tgt = target
    if dl > maxL { d = mul(d, maxL / dl); dl = maxL; tgt = add(root, d) }
    dl = max(dl, abs(a - b) + 0.01)
    let cosA = max(-1, min(1, (a * a + dl * dl - b * b) / (2 * a * dl)))
    let ang = acos(cosA)
    let u = mul(d, 1 / max(0.0001, len(d)))
    func r(_ s: CGFloat) -> CGPoint {
        CGPoint(x: u.x * cos(s * ang) - u.y * sin(s * ang), y: u.x * sin(s * ang) + u.y * cos(s * ang))
    }
    let e1 = add(root, mul(r(1), a)), e2 = add(root, mul(r(-1), a))
    let d1 = (e1.x - root.x) * pref.x + (e1.y - root.y) * pref.y
    let d2 = (e2.x - root.x) * pref.x + (e2.y - root.y) * pref.y
    return (d1 >= d2 ? e1 : e2, tgt)
}

enum YugongArt {
    // MARK: - figure

    static func figure(_ style: ArtStyle, _ state: PetState, t: Double, carrier: Double, night: Bool,
                       size: CGFloat, menuBar: Bool) -> NSImage {
        let (pose, k) = YugongRig.pose(state, t: t, night: night, stepped: style == .pixel)
        let fill = CGFloat(min(1.2, max(0, carrier)))
        switch style {
        case .ink:
            return NSImage(size: NSSize(width: size, height: size), flipped: true) { r in
                guard let c = NSGraphicsContext.current?.cgContext else { return false }
                c.saveGState()
                c.scaleBy(x: r.width / 100, y: r.height / 100)
                let pen = Pen(c: c, pixel: false, mb: menuBar, pal: .ink, ppu: r.width / 100)
                draw(pen, pose, k: k, fill: fill, bird: !menuBar)
                c.restoreGState()
                return true
            }
        case .pixel:
            let n = Int(menuBar ? size : (size / 3).rounded())
            let cg = pixelFigure(pose, k: k, fill: fill, grid: n, menuBar: menuBar, bird: !menuBar)
            return crisp(cg, size: NSSize(width: size, height: size))
        }
    }

    /// Pixel figure: flat body from the rig, outlined, then the hand-placed head on top.
    static func pixelFigure(_ pose: YPose, k: CGFloat, fill: CGFloat, grid n: Int, menuBar: Bool, bird: Bool) -> CGImage? {
        var spot: HeadSpot?
        return pixelLayer(n, n, { c in
            c.scaleBy(x: CGFloat(n) / 100, y: CGFloat(n) / 100)
            let pen = Pen(c: c, pixel: true, mb: menuBar || n < 30, pal: .pixel, ppu: CGFloat(n) / 100)
            spot = draw(pen, pose, k: k, fill: fill, bird: bird)
        }, after: { c in
            if let s = spot {
                PixelHeads.stamp(c, pose: pose, at: s, grid: n)
                if let h = s.hand { PixelHeads.blob(c, at: h, grid: n, fill: Palette.pixel.skin, w: n < 30 ? 2 : 3, h: n < 30 ? 2 : 3) }
                if let z = s.zzz { PixelHeads.zzz(c, above: z, k: s.birdK, grid: n) }
                if let q = s.clump { PixelHeads.blob(c, at: q, grid: n, fill: Palette.pixel.earth, w: n < 30 ? 2 : 4, h: n < 30 ? 2 : 3) }
                if let b = s.bird { PixelHeads.magpie(c, at: b, s.birdState, k: s.birdK, grid: n) }
            }
        })
    }

    /// Wraps a low-resolution bitmap so it always scales with whole, sharp pixels.
    static func crisp(_ cg: CGImage?, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { r in
            guard let cg, let c = NSGraphicsContext.current?.cgContext else { return false }
            c.interpolationQuality = .none
            c.draw(cg, in: r)
            return true
        }
    }

    /// Draws into a w x h pixel bitmap (y down, no anti-aliasing) and adds a 1-pixel dark
    /// outline around every opaque area.
    static func pixelLayer(_ w: Int, _ h: Int, outline: Bool = true, _ body: (CGContext) -> Void,
                           after: ((CGContext) -> Void)? = nil) -> CGImage? {
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: 1, y: -1)
        c.setShouldAntialias(false); c.setAllowsAntialiasing(false)
        c.interpolationQuality = .none
        c.saveGState(); body(c); c.restoreGState()
        guard outline, let data = c.data else { after?(c); return c.makeImage() }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var solid = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) { solid[i] = px[i * 4 + 3] > 127 }
        let o = Palette.pixel.outline.usingColorSpace(.sRGB)!
        let oc = [UInt8(o.redComponent * 255), UInt8(o.greenComponent * 255), UInt8(o.blueComponent * 255)]
        for y in 0..<h {
            for x in 0..<w where !solid[y * w + x] {
                let n = (x > 0 && solid[y * w + x - 1]) || (x < w - 1 && solid[y * w + x + 1])
                    || (y > 0 && solid[(y - 1) * w + x]) || (y < h - 1 && solid[(y + 1) * w + x])
                if n {
                    let i = (y * w + x) * 4
                    px[i] = oc[0]; px[i + 1] = oc[1]; px[i + 2] = oc[2]; px[i + 3] = 255
                }
            }
        }
        // whatever is half-transparent becomes fully opaque or vanishes: pixel art has no soft edges
        for i in 0..<(w * h) where px[i * 4 + 3] != 0 && px[i * 4 + 3] != 255 {
            if px[i * 4 + 3] > 127 {
                let a = CGFloat(px[i * 4 + 3]) / 255
                for ch in 0..<3 { px[i * 4 + ch] = UInt8(min(255, CGFloat(px[i * 4 + ch]) / a)) }
                px[i * 4 + 3] = 255
            } else { for ch in 0..<4 { px[i * 4 + ch] = 0 } }
        }
        after?(c)
        return c.makeImage()
    }

    // MARK: - the old man

    /// Squat, sturdy proportions: the body is drawn 6% wider and 10% shorter than the rig.
    static let bodyW: CGFloat = 1.06, bodyH: CGFloat = 0.9
    static func toCanvas(_ q: CGPoint) -> CGPoint { CGPoint(x: 50 + (q.x - 50) * bodyW, y: 94 + (q.y - 94) * bodyH) }

    /// Where the head went (canvas units), so pixel art can stamp its hand-placed head there.
    struct HeadSpot { let center: CGPoint; let mirror: Bool; var bird: CGPoint? = nil; var birdState = Bird.perch; var birdK: CGFloat = 0
        var hand: CGPoint? = nil; var clump: CGPoint? = nil; var zzz: CGPoint? = nil }

    @discardableResult
    static func draw(_ pn: Pen, _ p: YPose, k: CGFloat, fill: CGFloat, bird: Bool) -> HeadSpot {
        let pal = pn.pal, mb = pn.mb
        pn.c.saveGState()
        pn.c.translateBy(x: 50, y: 94); pn.c.scaleBy(x: bodyW, y: bodyH); pn.c.translateBy(x: -50, y: -94)
        if p.sq != 1 {
            let fx = (p.footF.x + p.footB.x) / 2
            pn.c.translateBy(x: fx, y: 94); pn.c.scaleBy(x: 1 / p.sq.squareRoot(), y: p.sq); pn.c.translateBy(x: -fx, y: -94)
        }
        defer { pn.c.restoreGState() }
        let hs: CGFloat = mb ? 1.55 : 1.38            // big head: it is what reads at small sizes
        let limb: CGFloat = mb ? 9 : 6.5
        let th = p.lean

        func T(_ x: CGFloat, _ y: CGFloat) -> CGPoint { add(p.hip, rot(CGPoint(x: x, y: y), th)) }
        let neck = T(-1.5, -24)
        let ha = th * 0.45 + p.head
        let hc = add(neck, rot(CGPoint(x: -1, y: -9 * hs), ha))
        func H(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            add(hc, rot(CGPoint(x: (p.lookBack ? -x : x) * hs, y: y * hs), p.lookBack ? -ha : ha))
        }

        // the A-frame carrier (jige): on his back, or standing on the ground behind him
        let jigeOrigin = p.jigeOnBack ? p.hip : CGPoint(x: p.sit ? 62 : 70, y: 79)
        let jigeAng = p.jigeOnBack ? th : -6
        func J(_ x: CGFloat, _ y: CGFloat) -> CGPoint { add(jigeOrigin, rot(CGPoint(x: x, y: y), jigeAng)) }
        drawJige(pn, J, fill: fill, onGround: !p.jigeOnBack)

        // shovel stuck in the ground or held
        let planted = p.handF != nil && p.handB != nil && !(p.handF! == p.gripLow)
        if !planted || p.sit { drawShovel(pn, p, k: k) }

        // back leg and back arm (a shade darker: they are farther away)
        let hipF = T(-3, 0), hipB = T(3, 0)
        let kneePref = p.sit ? CGPoint(x: -0.2, y: -1) : CGPoint(x: -1, y: 0.1)
        let (kneeB, footB) = joint(hipB, p.footB, 16, 16, pref: kneePref)
        pn.tube([hipB, kneeB, footB], limb + 1, pal.pantsDark, edge: !pn.pixel)
        sandal(pn, footB, dark: true)

        let shF = T(-2, -20), shB = T(2.5, -20)
        func elbowPref(_ hand: CGPoint, _ sh: CGPoint) -> CGPoint { hand.y < sh.y - 6 ? CGPoint(x: 1, y: 0.3) : CGPoint(x: 0.5, y: 1) }
        let (elB, hB) = joint(shB, p.handBack, 12, 12, pref: elbowPref(p.handBack, shB))
        pn.tube([shB, elB, hB], limb, pal.jacketDark, edge: !pn.pixel)
        pn.ellipse(hB, mb ? 6 : 4.6, mb ? 6 : 4.6, pal.skin, edge: !pn.pixel)

        // body: a padded jacket with a red sash
        let torso = pn.path([T(-8.5, -23), T(5, -24), T(9.5, -16), T(10, 5), T(-10.5, 5), T(-10, -14)], closed: true)
        pn.shape(torso, pal.jacket, edge: !pn.pixel)
        if !pn.pixel { wash(pn, torso, from: T(0, -6), to: T(0, 6)) }
        if !mb && !pn.pixel { pn.shape(pn.path([T(-10.3, -4), T(9.9, -4), T(9.9, 0), T(-10.4, 0)], closed: true), pal.sash) }
        else { pn.tube([T(-9, -2), T(9, -2)], 2.6, pal.sash, edge: false) }

        // front leg
        let (kneeF, footF) = joint(hipF, p.footF, 16, 16, pref: kneePref)
        pn.tube([hipF, kneeF, footF], limb + 1, pal.pants, edge: !pn.pixel)
        sandal(pn, footF, dark: false)

        if planted && !p.sit { drawShovel(pn, p, k: k) }

        // head: white topknot hair, face, beard, then the straw hat (pixel art stamps it afterwards)
        if !pn.pixel {
            pn.c.saveGState()
            pn.c.translateBy(x: hc.x, y: hc.y); pn.c.scaleBy(x: 1 / bodyW, y: 1 / bodyH); pn.c.translateBy(x: -hc.x, y: -hc.y)
            head(pn, p, hc: hc, ha: ha, hs: hs)
            pn.c.restoreGState()
        }

        // front arm over everything else on the body
        let (elF, hF) = joint(shF, p.handFront, 12, 12, pref: elbowPref(p.handFront, shF))
        pn.tube([shF, elF, hF], limb, pn.pixel ? pal.jacketLight : pal.jacket, edge: !pn.pixel)
        pn.ellipse(hF, mb ? 6.4 : 5, mb ? 6.4 : 5, pal.skin, edge: !pn.pixel)

        effects(pn, p, k: k, H, hc: hc)
        let perch = J(18.5, -53)
        if bird && !pn.pixel { magpie(pn, at: perch, p.bird, k: k) }
        var spot = HeadSpot(center: toCanvas(hc), mirror: p.lookBack, bird: bird ? toCanvas(perch) : nil, birdState: p.bird, birdK: k)
        if pn.pixel {   // things that pass in front of the hand-placed head are stamped after it
            if p.handF != nil && hF.y < hc.y + 12 { spot.hand = toCanvas(hF) }   // wiping sweat, yawning
            spot.clump = clumpPoint(p, k: k, pixel: true).map(toCanvas)
            if p.fx == .zzz { spot.zzz = toCanvas(hc) }
        }
        return spot
    }

    /// The head alone (also used by the character sheet's expression row).
    static func head(_ pn: Pen, _ p: YPose, hc: CGPoint, ha: CGFloat, hs: CGFloat) {
        let pal = pn.pal, mb = pn.mb
        // draw in head space: origin at the head centre, scaled, mirrored when he looks back
        let c = pn.c
        c.saveGState()
        c.translateBy(x: hc.x, y: hc.y)
        let a = ha * .pi / 180
        c.rotate(by: p.lookBack ? a : -a)
        c.scaleBy(x: p.lookBack ? -hs : hs, y: hs)
        var hp = pn; hp.ppu *= hs; hp.olScale = hs
        let H: (CGFloat, CGFloat) -> CGPoint = { CGPoint(x: $0, y: $1) }
        hp.ellipse(H(7, 1.5), 7, 9, pal.beard)
        hp.ellipse(.zero, 19, 19, pal.skin)
        if !mb { hp.ellipse(H(4.2, 1.5), 3.4, 4.4, pal.skin) }
        face(hp, p, H, hs: hs)
        hat(hp, p, H, hs: hs)
        c.restoreGState()
    }

    /// Ink style: a soft wash of shadow pooling toward `to`, clipped to the shape, outline redrawn.
    static func wash(_ pn: Pen, _ shape: CGPath, from a: CGPoint, to b: CGPoint, strength: CGFloat = 0.32) {
        let c = pn.c
        c.saveGState()
        c.addPath(shape); c.clip()
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
            pn.pal.outline.withAlphaComponent(0).cgColor, pn.pal.outline.withAlphaComponent(strength).cgColor] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g, start: a, end: b, options: [.drawsAfterEndLocation])
        c.restoreGState()
        c.addPath(shape); c.setStrokeColor(pn.pal.outline.cgColor); c.setLineWidth(pn.ol); c.strokePath()
    }

    static func sandal(_ pn: Pen, _ f: CGPoint, dark: Bool) {
        pn.ellipse(CGPoint(x: f.x - 2.5, y: f.y - 1.6), pn.mb ? 11 : 9, pn.mb ? 5 : 4, dark ? pn.pal.woodDark : pn.pal.wood)
    }

    static func drawJige(_ pn: Pen, _ J: (CGFloat, CGFloat) -> CGPoint, fill: CGFloat, onGround: Bool) {
        let pal = pn.pal, mb = pn.mb
        let pole: CGFloat = mb ? 4.5 : 3.2
        // far pole, then the basket (set low and far back so the earth shows past the hat), near pole
        pn.tube([J(9, 14), J(14, -50)], pole, pal.woodDark)
        if onGround {   // forked prop stick that keeps it standing
            pn.tube([J(16, -20), CGPoint(x: J(16, -20).x + 14, y: 94)], pole * 0.8, pal.woodDark)
        }
        // at menu-bar size the basket sits lower and darker, so it never reads as hair
        let dy: CGFloat = mb ? 17 : 0
        let rimA = J(13, -30 + dy), rimB = J(34, -35 + dy), botB = J(31, -6 + dy * 0.5), botA = J(16, -4 + dy * 0.5)
        let basket = pn.path([rimA, rimB, botB, botA], closed: true)
        let h = (3 + 21 * fill) * (fill < 0.04 ? 0 : 1)
        if h > 0 {
            let mid = mul(add(rimA, rimB), 0.5)
            let up = rot(CGPoint(x: 2, y: -h * 1.8), onGround ? -6 : 0)
            let ctl = add(mid, up)
            let m = CGMutablePath()
            m.move(to: add(rimA, CGPoint(x: -1, y: 1)))
            m.addQuadCurve(to: add(rimB, CGPoint(x: 1, y: 1)), control: ctl)
            m.closeSubpath()
            pn.shape(m, pal.earth)
            if !mb {
                let top = add(mid, mul(up, 0.42))
                pn.dot(add(top, CGPoint(x: -3, y: 1)), 1, pal.earthDark)
                pn.dot(add(top, CGPoint(x: 3, y: 2.5)), 0.8, pal.earthDark)
                if fill >= 1 { pn.dot(add(top, CGPoint(x: 0, y: -1.5)), 1.1, pal.earthDark) }
            }
        }
        pn.shape(basket, mb ? pal.hatDark : pal.hat)
        if !mb {
            for i in 1...3 {
                let u = CGFloat(i) / 4
                pn.brush([add(rimA, mul(sub(botA, rimA), u)), add(rimB, mul(sub(botB, rimB), u))], pn.pixel ? 1 : 0.9, pal.hatDark)
            }
        }
        pn.tube([J(13, 16), J(18.5, -52)], pole, pal.wood)
        pn.tube([J(9, -18), J(17, -18)], pole * 0.7, pal.wood, edge: !mb)
    }

    static func drawShovel(_ pn: Pen, _ p: YPose, k: CGFloat) {
        let pal = pn.pal, mb = pn.mb
        let d = p.toolDir, n = CGPoint(x: d.y, y: -d.x)
        let top = p.toolTop
        let base = add(top, mul(d, 40))
        let bw: CGFloat = pn.pixel ? 1.35 : 1        // a broader blade so it reads in pixels
        pn.tube([add(top, mul(n, 3.2)), add(top, mul(n, -3.2))], mb ? 3.6 : 2.6, pal.woodDark)   // T-grip
        pn.tube([top, base], mb ? 4.2 : (pn.pixel ? 3.4 : 2.8), pal.wood)
        let blade = pn.path([add(base, mul(n, 5.2 * bw)), add(add(base, mul(d, 8 * bw)), mul(n, 4.2 * bw)), add(base, mul(d, 14 * bw)),
                             add(add(base, mul(d, 8 * bw)), mul(n, -4.2 * bw)), add(base, mul(n, -5.2 * bw))], closed: true)
        pn.shape(blade, pal.iron)
        if !mb && !pn.pixel { pn.brush([add(base, mul(d, 2)), add(base, mul(d, 10))], 1.0, pal.ironDark) }
        if p.clump == .onBlade {
            pn.ellipse(add(add(base, mul(d, 7)), mul(n, p.toolAng > 90 ? 3 : -3)), 9, 6, pal.earth)
        }
    }

    /// Ink-style face (the pixel style uses hand-placed heads instead).
    static func face(_ pn: Pen, _ p: YPose, _ H: (CGFloat, CGFloat) -> CGPoint, hs: CGFloat) {
        let pal = pn.pal, mb = pn.mb
        let lw: CGFloat = mb ? 2.0 : 1.15
        // eyes
        for e in [H(-4.6, -2.2), H(1.8, -2.2)] {
            switch p.eyes {
            case .open:
                pn.dot(e, mb ? 2.0 : 1.55)
                if !mb { pn.dot(add(e, CGPoint(x: -0.5, y: -0.55)), 0.5, .white) }
            case .closed:
                pn.brush([add(e, CGPoint(x: -2, y: -0.3)), add(e, CGPoint(x: 0, y: 1)), add(e, CGPoint(x: 2, y: -0.3))], lw)
            case .happy:
                pn.brush([add(e, CGPoint(x: -2, y: 1)), add(e, CGPoint(x: 0, y: -1)), add(e, CGPoint(x: 2, y: 1))], lw)
            case .squeeze:
                pn.brush([add(e, CGPoint(x: -1.6, y: -1.3)), add(e, CGPoint(x: 1.4, y: 0)), add(e, CGPoint(x: -1.6, y: 1.3))], lw)
            }
        }
        // bushy white brows that droop at the ends
        if !mb {
            pn.ellipse(H(-5, -5.7), 6.4, 3.0, pal.beard, rot: 0.3)
            pn.ellipse(H(2.4, -5.6), 5.0, 2.6, pal.beard, rot: -0.3)
        }
        pn.ellipse(H(-0.8, 1.0), mb ? 4 : 4.6, mb ? 2.4 : 2.6, pal.blush, edge: false)
        // the big white beard covers the whole lower face
        let beard = CGMutablePath()
        beard.move(to: H(-10.5, 2.2))
        beard.addQuadCurve(to: H(-4 + p.beard, 19.5), control: H(-12, 13))
        beard.addQuadCurve(to: H(7, 1.5), control: H(7.5, 12))
        beard.addQuadCurve(to: H(-10.5, 2.2), control: H(-2, 7))
        pn.shape(beard, pal.beard)
        if !mb {
            pn.brush([H(-5, 10), H(-4.5 + p.beard * 0.6, 16)], 0.9, pal.beardShade)
            pn.brush([H(0, 9), H(-1 + p.beard * 0.6, 14)], 0.9, pal.beardShade)
        }
        switch p.mouth {
        case .open: pn.ellipse(H(-5, 7.6), 3.6, 2.8, pal.mouth)
        case .yawn: pn.ellipse(H(-5, 8.6), 4.6, 6.0, pal.mouth)
        case .snore: pn.ellipse(H(-5, 7.4), 2.2, 2.2, pal.mouth)
        case .smile: break
        }
        // moustache in two soft puffs, then the round rosy nose
        pn.ellipse(H(-8.6, 4.2), 7.4, 3.9, pal.beard, rot: -0.25)
        pn.ellipse(H(-3.4, 4.4), 7.0, 3.6, pal.beard, rot: 0.2)
        pn.ellipse(H(-9.3, 1.0), mb ? 6 : 4.6, mb ? 5.4 : 4.2, pal.nose)
    }

    static func hat(_ pn: Pen, _ p: YPose, _ H: (CGFloat, CGFloat) -> CGPoint, hs: CGFloat) {
        let pal = pn.pal, mb = pn.mb
        let tip = p.hatTip
        func Q(_ x: CGFloat, _ y: CGFloat) -> CGPoint {     // hat space: tips forward over the eyes when he naps
            let v = rot(CGPoint(x: x, y: y), 24 * tip)
            return H(v.x - 1.5 * tip, v.y + 4.5 * tip)
        }
        // crown first (behind the front brim), then the wide brim
        let crown = CGMutablePath()
        crown.move(to: Q(-7.5, -7.2))
        crown.addCurve(to: Q(1, -17.5), control1: Q(-8, -12), control2: Q(-5, -17.5))
        crown.addCurve(to: Q(8.5, -7.2), control1: Q(6, -17.5), control2: Q(8.8, -12))
        crown.closeSubpath()
        pn.shape(crown, pal.hat)
        if !pn.pixel { wash(pn, crown, from: Q(-4, -14), to: Q(8, -8), strength: 0.22) }
        pn.shape(pn.path([Q(-7.6, -10.6), Q(8.6, -10.6), Q(8.7, -8), Q(-7.8, -8)], closed: true), pal.band, edge: !mb)
        let brim = CGMutablePath()
        let w: CGFloat = mb ? 16.5 : 16
        brim.move(to: Q(-w, -5.4))
        brim.addQuadCurve(to: Q(w + 1, -6.0), control: Q(0.5, -11.5))
        brim.addQuadCurve(to: Q(-w, -5.4), control: Q(0.5, -1.2))
        brim.closeSubpath()
        pn.shape(brim, pal.hat)
        if !mb {
            // woven straw: a few radial strands, ragged ends at the front
            for x: CGFloat in [-11, -5.5, 6, 11.5] {
                pn.brush([Q(x * 0.55, -8.2), Q(x, -5.6)], pn.pixel ? 1 : 0.7, pal.hatDark)
            }
            if !pn.pixel { pn.brush([Q(-w - 1.5, -4.6), Q(-w + 1, -5.4)], 0.8, pal.hatDark) }
        }
    }

    /// Where the tossed clump of earth is (rig units), or nil when nothing is in the air.
    static func clumpPoint(_ p: YPose, k: CGFloat, pixel: Bool) -> CGPoint? {
        let u: CGFloat = pixel ? floor(k * 3) / 3 + 0.17 : k
        guard p.clump == .flying, u < 0.9 else { return nil }
        let d = p.toolDir
        let from = add(p.toolTop, mul(d, 47)), to = add(p.hip, rot(CGPoint(x: 24, y: -36), p.lean))
        let mid = CGPoint(x: (from.x + to.x) / 2, y: min(from.y, to.y) - 16)
        return CGPoint(x: (1 - u) * (1 - u) * from.x + 2 * (1 - u) * u * mid.x + u * u * to.x,
                       y: max(4, (1 - u) * (1 - u) * from.y + 2 * (1 - u) * u * mid.y + u * u * to.y))
    }

    static func effects(_ pn: Pen, _ p: YPose, k: CGFloat, _ H: (CGFloat, CGFloat) -> CGPoint, hc: CGPoint) {
        let pal = pn.pal, mb = pn.mb
        let step: CGFloat = pn.pixel ? floor(k * 3) / 3 + 0.17 : k
        func drop(_ at: CGPoint, _ s: CGFloat) {
            let m = CGMutablePath()
            m.move(to: CGPoint(x: at.x, y: at.y - 2.6 * s))
            m.addQuadCurve(to: CGPoint(x: at.x, y: at.y + 1.6 * s), control: CGPoint(x: at.x + 2.6 * s, y: at.y + 1 * s))
            m.addQuadCurve(to: CGPoint(x: at.x, y: at.y - 2.6 * s), control: CGPoint(x: at.x - 2.6 * s, y: at.y + 1 * s))
            pn.shape(m, pal.sweat, edge: !mb)
        }
        if p.sweat { drop(H(-12, -3), mb ? 2 : 1.3); if !mb { drop(H(10.5, 0), 1.0) } }
        switch p.fx {
        case .sweatFly:
            drop(add(H(9, -6), CGPoint(x: 9 * step, y: -5 * step + 8 * step * step)), mb ? 1.8 : 1.2)
        case .zzz where pn.pixel: break      // stamped on the pixel grid afterwards
        case .zzz:
            for i in 0..<(mb ? 1 : 3) {
                let u = (step + CGFloat(i) / 3).truncatingRemainder(dividingBy: 1)
                let s: CGFloat = (mb ? 9 : 4.5) * (0.6 + 0.6 * u)
                let o = add(hc, CGPoint(x: -6 - 8 * u, y: -18 - 16 * u))
                let z = [o, CGPoint(x: o.x + s, y: o.y), CGPoint(x: o.x, y: o.y + s), CGPoint(x: o.x + s, y: o.y + s)]
                pn.c.setLineCap(.round); pn.c.setLineJoin(.round)
                pn.c.addPath(pn.path(z)); pn.c.setStrokeColor((pn.pixel ? pal.birdBlue : pal.outline).cgColor)
                pn.c.setLineWidth(pn.pixel ? pn.px(1) : (mb ? 2.8 : 1.2)); pn.c.strokePath()
            }
        case .notes where !mb && !pn.pixel:
            let o = add(hc, CGPoint(x: 18 + 3 * step, y: -22 - 4 * step))
            pn.dot(o, 1.4); pn.brush([o, add(o, CGPoint(x: 1.2, y: -6))], 0.9)
            pn.brush([add(o, CGPoint(x: 1.2, y: -6)), add(o, CGPoint(x: 3.6, y: -4.6))], 0.9)
        case .sparkle where !mb && !pn.pixel:
            for (i, d) in [CGPoint(x: -15, y: -16), CGPoint(x: 13, y: -22), CGPoint(x: -20, y: 2)].enumerated() {
                let s: CGFloat = (i == Int(step * 3) % 3) ? 3.2 : 2
                let o = add(hc, d)
                pn.brush([CGPoint(x: o.x - s, y: o.y), CGPoint(x: o.x + s, y: o.y)], 0.9, pal.hatDark)
                pn.brush([CGPoint(x: o.x, y: o.y - s), CGPoint(x: o.x, y: o.y + s)], 0.9, pal.hatDark)
            }
        case .pant where !mb:
            let o = H(-13, 8)
            pn.brush([o, add(o, CGPoint(x: -3, y: -1))], 0.8, pal.beardShade)
            pn.brush([add(o, CGPoint(x: 0, y: 3)), add(o, CGPoint(x: -3, y: 3.5))], 0.8, pal.beardShade)
        default: break
        }
        if !pn.pixel, let q = clumpPoint(p, k: k, pixel: false) {
            // earth tossed over his shoulder into the basket
            pn.ellipse(q, mb ? 8 : 6, mb ? 6.5 : 4.6, pal.earth, edge: true)
            if !mb { pn.dot(add(q, CGPoint(x: -5, y: 3)), 0.9, pal.earthDark); pn.dot(add(q, CGPoint(x: 4, y: 4)), 0.7, pal.earthDark) }
        }
    }

    // MARK: - the magpie

    static func magpie(_ pn: Pen, at foot: CGPoint, _ b: Bird, k: CGFloat, scale: CGFloat = 1) {
        let pal = pn.pal
        let hop: CGFloat = b == .hop ? -4 * sin(.pi * min(1, (pn.pixel ? floor(k * 3) / 3 + 0.17 : k) * 2)) : 0
        func B(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: foot.x + x * scale, y: foot.y + (y + hop) * scale) }
        pn.brush([B(1, -1), B(-1, 0.6)], 0.8)
        pn.tube([B(4, -4.5), B(13, -1.5)], 2.6 * scale, pal.bird)                       // long tail
        pn.ellipse(B(1.5, -5.2), 10 * scale, 6.2 * scale, pal.bird)                     // body
        pn.ellipse(B(-0.6, -3.8), 5.4 * scale, 3.6 * scale, pal.birdWhite, edge: false) // white belly
        pn.ellipse(B(3.2, -5.8), 4.2 * scale, 1.9 * scale, pn.pixel ? pal.birdBlue : pal.birdWhite, edge: false)
        let head = b == .sleep ? B(-2.5, -7) : B(-3.6, -8.8)
        pn.ellipse(head, 5.6 * scale, 5.4 * scale, pal.bird)
        if b == .sleep {
            pn.brush([add(head, CGPoint(x: -1.6, y: -0.4)), add(head, CGPoint(x: -0.4, y: 0.2))], 0.6, .white)
        } else {
            pn.dot(add(head, CGPoint(x: -1.1, y: -0.6)), 0.6, .white, pixels: 1)
            let open: CGFloat = b == .chirp ? 1.3 : 0.2
            pn.shape(pn.path([add(head, CGPoint(x: -2.4, y: -0.8)), add(head, CGPoint(x: -5.2, y: 0 - open * 0.3)),
                              add(head, CGPoint(x: -2.4, y: 0.6))], closed: true), pal.outline, edge: false)
            if open > 1 {
                pn.shape(pn.path([add(head, CGPoint(x: -2.4, y: 0.6)), add(head, CGPoint(x: -4.8, y: 2.0)),
                                  add(head, CGPoint(x: -2.4, y: 1.2))], closed: true), pal.outline, edge: false)
            }
        }
    }
}
