import AppKit

// Two more of Yugong's household from the Liezi tale (愚公移山):
//   the son (子)          - "broke the stones and dug the soil" (叩石墾壤): a pickaxe at the mountain's foot
//   the neighbour's boy   - the widow Jingcheng's seven-year-old, who "jumped up and went to help" (跳往助之)
// Pixel art like the grandson: shapes in figure units (0...100, y down) rasterized on a small grid,
// then the 1-pixel outline pass. Each carries a meter: the son's heap of broken stone, the boy's basket.

private func hex(_ h: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: 1)
}

enum FamilyColors {
    static let shirt = hex(0xEFE7D6), shirtShade = hex(0xC9BFA9)
    static let vest = hex(0x7A5230), trousers = hex(0x4B5263), trousersDark = hex(0x363B49)
    static let headband = hex(0xFAF7EF), stone = hex(0x9AA0A6), stoneDark = hex(0x6E747B)
    static let boyJacket = hex(0xF6C945), boyTrousers = hex(0xF2A2B8), ribbon = hex(0xE0503C)
    static let sleeve = [hex(0xE0503C), hex(0xF6C945), hex(0x4FAF5A), hex(0x4A7BD1), hex(0xF28DB2)]   // 색동 stripes
}

/// The son's routine: lean on the pickaxe, wind up, strike; sits on a rock when his heap is full.
public enum SonPose: CaseIterable { case lean, raise, strike, rest }
/// The boy's routine: carry, crouch, hop; sits down when his basket is full.
public enum BoyPose: CaseIterable { case carry, crouch, hop, rest }

/// Hand-placed heads, one character per pixel, stamped after the outline pass (like Grandpa's).
enum FamilyHeads {
    static let colors: [Character: NSColor] = {
        let p = Palette.pixel
        return ["o": p.outline, "k": p.kidHair, "s": p.skin, "p": p.blush, "m": p.mouth,
                "w": FamilyColors.headband, "r": FamilyColors.ribbon]
    }()
    /// The son, looking left: topknot, white headband tied at the back, a short dark beard.
    static let son: [String] = [
        "....ooo......",
        "...okkko.....",
        "..ookkkoo....",
        ".okkkkkkkoo..",
        "okkkkkkkkkko.",
        "owwwwwwwwwwwo",
        "oskssskskkowo",
        "osssssssskkow",
        "osssssspskko.",
        ".okkssskkso..",
        "..okmkkkso...",
        "...ooooooo...",
    ]
    static let sonAnchor = (x: 6, y: 6)
    /// The neighbour's boy, drawn looking left and mirrored: two tufts tied with red.
    static let boy: [String] = [
        "..oo...oo...",
        ".okko.okko..",
        ".okko.okko..",
        "..orroorro..",
        ".okkkkkkkko.",
        "okkkkkkkkkko",
        "ossskkkkkkko",
        "osksssksskko",
        "osssssssssko",
        "opsmsssspko.",
        ".ossssssso..",
        "..ooooooo...",
    ]
    static let boyAnchor = (x: 5, y: 7)

    /// Stamps `rows` with its anchor at canvas point `c` (units 0...100) on an n-pixel grid.
    static func stamp(_ ctx: CGContext, _ rows: [[Character]], anchor: (x: Int, y: Int), at c: CGPoint, grid n: Int, mirror: Bool) {
        let w = rows.first?.count ?? 0
        let ox = Int((c.x * CGFloat(n) / 100).rounded()) - (mirror ? w - 1 - anchor.x : anchor.x)
        let oy = Int((c.y * CGFloat(n) / 100).rounded()) - anchor.y
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch != "." {
                guard let col = colors[ch] else { continue }
                ctx.setFillColor(col.cgColor)
                ctx.fill(CGRect(x: ox + (mirror ? w - 1 - x : x), y: oy + y, width: 1, height: 1))
            }
        }
    }
}

extension YugongArt {
    // MARK: - the son

    /// Draws the son's body; returns where his head goes (canvas units) and a hand that passes over it.
    static func son(_ pn: Pen, _ pose: SonPose, fill: Double) -> (head: CGPoint, hand: CGPoint?) {
        let pal = pn.pal, F = FamilyColors.self
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        // his meter: a heap of broken stone behind him (right), growing with the fill
        let f = CGFloat(min(1.1, max(0, fill)))
        if f > 0.03 {
            let h = 6 + 18 * f
            pn.shape(pn.path([P(64, 94), P(70, 94 - h * 0.7), P(78, 94 - h), P(88, 94 - h * 0.6), P(96, 94)], closed: true), F.stone, edge: false)
            pn.dot(P(74, 94 - h * 0.45), F.stoneDark); pn.dot(P(84, 94 - h * 0.3), F.stoneDark)
        }
        if pose == .rest {
            // sitting on a rock, the pickaxe down beside him, wiping his brow
            pn.ellipse(P(50, 86), 30, 14, F.stone, edge: false)
            pick(pn, grip: P(8, 92), head: P(36, 92))
            pn.tube([P(46, 76), P(30, 80), P(26, 93)], 9, F.trousers, edge: false)
            pn.tube([P(52, 76), P(38, 82), P(36, 93)], 9, F.trousersDark, edge: false)
            body(pn, dy: 14)
            pn.tube([P(54, 60), P(46, 70), P(40, 74)], 6, F.shirt, edge: false)            // hand on the knee
            pn.tube([P(38, 60), P(30, 52), P(28, 44)], 6, F.shirt, edge: false)            // up to his brow
            return (P(45, 43), P(30, 38))
        }
        // legs: back leg darker
        pn.tube([P(50, 66), P(56, 80), P(56, 93)], 9, F.trousersDark, edge: false)
        pn.tube([P(42, 66), P(38, 80), P(36, 93)], 9, F.trousers, edge: false)
        body(pn, dy: 0)
        // arms and the pickaxe
        let shF = P(38, 46), shB = P(54, 46)
        switch pose {
        case .lean:
            pick(pn, grip: P(28, 50), head: P(26, 92))
            pn.tube([shB, P(42, 56), P(30, 52)], 6, F.shirtShade, edge: false)
            pn.tube([shF, P(32, 54), P(28, 50)], 6, F.shirt, edge: false)
            pn.ellipse(P(28, 50), 6, 6, pal.skin, edge: false)
        case .raise:
            pick(pn, grip: P(64, 34), head: P(86, 10))
            pn.tube([shB, P(62, 44), P(64, 34)], 6, F.shirtShade, edge: false)
            pn.tube([shF, P(52, 44), P(62, 36)], 6, F.shirt, edge: false)
            pn.ellipse(P(64, 34), 6, 6, pal.skin, edge: false)
        case .strike:
            pick(pn, grip: P(32, 62), head: P(10, 84))
            pn.tube([shB, P(44, 60), P(34, 62)], 6, F.shirtShade, edge: false)
            pn.tube([shF, P(32, 54), P(32, 62)], 6, F.shirt, edge: false)
            pn.ellipse(P(32, 62), 6, 6, pal.skin, edge: false)
            for (x, y) in [(4.0, 82.0), (14, 80), (8, 76)] { pn.dot(P(CGFloat(x), CGFloat(y)), F.stone) }   // chips fly
        case .rest: break
        }
        return (P(45, 29), nil)
    }

    private static func body(_ pn: Pen, dy: CGFloat) {
        let F = FamilyColors.self
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y + dy) }
        pn.shape(pn.path([P(34, 42), P(58, 42), P(60, 70), P(32, 70)], closed: true), F.shirt, edge: false)
        pn.shape(pn.path([P(40, 43), P(56, 43), P(58, 66), P(42, 66)], closed: true), F.vest, edge: false)   // the vest, seen from his left
        pn.tube([P(33, 66), P(59, 66)], 3, F.trousersDark, edge: false)                                        // belt
    }

    /// A pickaxe: wooden handle from the grip to the head, the iron head across it at the far end.
    private static func pick(_ pn: Pen, grip: CGPoint, head: CGPoint) {
        let pal = pn.pal
        pn.tube([grip, head], 3.4, pal.wood, edge: false)
        let dx = head.x - grip.x, dy = head.y - grip.y, len = max(0.01, (dx * dx + dy * dy).squareRoot())
        let n = CGPoint(x: -dy / len * 11, y: dx / len * 11), back = CGPoint(x: -dx / len * 3, y: -dy / len * 3)
        pn.tube([CGPoint(x: head.x + n.x + back.x, y: head.y + n.y + back.y), head,
                 CGPoint(x: head.x - n.x + back.x, y: head.y - n.y + back.y)], 3.6, pal.iron, edge: false)
    }

    // MARK: - the neighbour's boy

    /// Draws the boy's body; returns where his head goes (canvas units).
    static func boy(_ pn: Pen, _ pose: BoyPose, fill: Double) -> CGPoint {
        let pal = pn.pal, F = FamilyColors.self
        let lift: CGFloat = pose == .hop ? -12 : pose == .crouch ? 4 : 0
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y + lift) }
        func basket(_ at: CGPoint) {
            let f = CGFloat(min(1.1, max(0, fill)))
            if f > 0.03 {
                let m = CGMutablePath(); m.move(to: CGPoint(x: at.x - 11, y: at.y))
                m.addQuadCurve(to: CGPoint(x: at.x + 11, y: at.y), control: CGPoint(x: at.x, y: at.y - 22 * f)); m.closeSubpath()
                pn.shape(m, pal.earth, edge: false)
            }
            pn.shape(pn.path([CGPoint(x: at.x - 12, y: at.y), CGPoint(x: at.x + 12, y: at.y),
                              CGPoint(x: at.x + 8, y: at.y + 11), CGPoint(x: at.x - 8, y: at.y + 11)], closed: true), pal.hat, edge: false)
        }
        if pose == .rest {
            basket(CGPoint(x: 80, y: 82))
            pn.tube([P(46, 80), P(62, 86), P(70, 92)], 9, F.boyTrousers, edge: false)
            pn.shape(pn.path([P(36, 58), P(60, 58), P(62, 84), P(34, 84)], closed: true), F.boyJacket, edge: false)
            sleeve(pn, [P(40, 62), P(36, 74), P(40, 84)])
            return P(48, 42)
        }
        // legs: tucked up in the hop, wide on the crouch
        if pose == .hop {
            pn.tube([P(44, 76), P(38, 84), P(46, 90)], 8, F.boyTrousers, edge: false)
            pn.tube([P(54, 76), P(58, 84), P(64, 88)], 8, F.boyTrousers, edge: false)
        } else {
            let w: CGFloat = pose == .crouch ? 10 : 6
            pn.tube([P(46, 76), P(46 - w, 93 - lift)], 8, F.boyTrousers, edge: false)
            pn.tube([P(54, 76), P(54 + w, 93 - lift)], 8, F.boyTrousers, edge: false)
        }
        pn.shape(pn.path([P(38, 54), P(62, 54), P(64, 78), P(36, 78)], closed: true), F.boyJacket, edge: false)
        pn.tube([P(38, 74), P(62, 74)], 3, F.ribbon, edge: false)                       // sash
        basket(P(74, 70))
        sleeve(pn, [P(58, 58), P(66, 64), P(70, 70)])                                   // both hands on the basket
        return P(50, 36)
    }

    /// A 색동 sleeve: the arm in rainbow stripes, then the hand.
    private static func sleeve(_ pn: Pen, _ pts: [CGPoint]) {
        guard let a = pts.first, let b = pts.last else { return }
        let n = FamilyColors.sleeve.count
        for i in 0..<n {
            let u0 = CGFloat(i) / CGFloat(n), u1 = CGFloat(i + 1) / CGFloat(n)
            func at(_ u: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u) }
            pn.tube([at(u0), at(u1)], 7, FamilyColors.sleeve[i], edge: false)
        }
        pn.ellipse(b, 6, 6, pn.pal.skin, edge: false)
    }

    // MARK: - layers

    /// The son on an n-cell grid (32 in the scene and on the sheet).
    public static func sonLayer(_ pose: SonPose, fill: Double, grid n: Int = 32) -> CGImage? {
        var spot: (head: CGPoint, hand: CGPoint?) = (.zero, nil)
        return pixelLayer(n, n, { c in
            c.scaleBy(x: CGFloat(n) / 100, y: CGFloat(n) / 100)
            spot = son(Pen(c: c, mb: true, pal: .pixel, ppu: CGFloat(n) / 100), pose, fill: fill)
        }, after: { c in
            var rows = FamilyHeads.son.map { Array($0) }
            if pose == .strike || pose == .rest { rows[6][2] = "s"; rows[6][6] = "s"; rows[7][2] = "k"; rows[7][6] = "k" }   // eyes squeezed
            FamilyHeads.stamp(c, rows, anchor: FamilyHeads.sonAnchor, at: spot.head, grid: n, mirror: false)
            if let h = spot.hand { PixelHeads.blob(c, at: h, grid: n, fill: Palette.pixel.skin, w: 2, h: 2) }
        })
    }

    /// The neighbour's boy on an n-cell grid (22 in the scene and on the sheet).
    public static func boyLayer(_ pose: BoyPose, fill: Double, grid n: Int = 22) -> CGImage? {
        var head = CGPoint.zero
        return pixelLayer(n, n, { c in
            c.scaleBy(x: CGFloat(n) / 100, y: CGFloat(n) / 100)
            head = boy(Pen(c: c, mb: true, pal: .pixel, ppu: CGFloat(n) / 100), pose, fill: fill)
        }, after: { c in
            var rows = FamilyHeads.boy.map { Array($0) }
            if pose == .rest { rows[9][3] = "s"; rows[7][2] = "s"; rows[7][6] = "s"; rows[8][2] = "k"; rows[8][6] = "k" }   // sleepy
            if pose == .hop { rows[9][3] = "o" }                                                                            // open-mouthed "hup!"
            FamilyHeads.stamp(c, rows, anchor: FamilyHeads.boyAnchor, at: head, grid: n, mirror: true)
        })
    }
}

// MARK: - the family sheet (review before animating)

extension YugongSheet {
    public static let familySize = NSSize(width: 2000, height: 1500)

    /// The son and the neighbour's boy: every pose at 8x, their meters, a mock of the whole household
    /// in the popover scene, and the new colours. Draws into the current flipped context.
    public static func drawFamilySheet() {
        NSColor.white.setFill(); NSRect(origin: .zero, size: familySize).fill()
        let ink = NSColor(srgbRed: 0x26 / 255.0, green: 0x21 / 255.0, blue: 0x1D / 255.0, alpha: 1)
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ w: NSFont.Weight = .regular,
                  _ col: NSColor = ink, width: CGFloat = 0) {
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: w), .foregroundColor: col]
            if width > 0 { (s as NSString).draw(in: NSRect(x: x, y: y, width: width, height: 300), withAttributes: a) }
            else { (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: a) }
        }
        func card(_ img: CGImage?, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat) {
            NSColor(white: 0, alpha: 0.04).setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: s, height: s), xRadius: 12, yRadius: 12).fill()
            YugongArt.crisp(img, size: NSSize(width: s, height: s)).draw(in: NSRect(x: x, y: y, width: s, height: s))
        }
        text("우공네 식구  Yugong's household", 60, 40, 56, .heavy)
        text("Character sheet — two new members, pixel art. Each can be given an AI to watch (the grandfather is the main one).",
             60, 112, 24, .regular, NSColor(white: 0.4, alpha: 1))

        let rows: [(String, String, [(String, CGImage?)], [CGImage?])] = [
            ("아들  The son", "\u{201C}Broke the stones and dug the soil\u{201D} (叩石墾壤). Steady and strong; a pickaxe at the mountain's foot. His meter: the heap of broken stone.",
             [("기대기 lean", YugongArt.sonLayer(.lean, fill: 0.5)), ("들기 raise", YugongArt.sonLayer(.raise, fill: 0.5)),
              ("내려치기 strike", YugongArt.sonLayer(.strike, fill: 0.5)), ("쉬기 rest (full)", YugongArt.sonLayer(.rest, fill: 1))],
             [0, 0.5, 1].map { YugongArt.sonLayer(.lean, fill: $0) }),
            ("이웃집 아이  The neighbour's boy", "The widow Jingcheng's seven-year-old, who \u{201C}jumped up and went to help\u{201D} (跳往助之). 색동 sleeves, a little 삼태기 basket. His meter: the earth in it.",
             [("나르기 carry", YugongArt.boyLayer(.carry, fill: 0.5, grid: 22)), ("웅크리기 crouch", YugongArt.boyLayer(.crouch, fill: 0.5, grid: 22)),
              ("깡충 hop", YugongArt.boyLayer(.hop, fill: 0.5, grid: 22)), ("쉬기 rest (full)", YugongArt.boyLayer(.rest, fill: 1, grid: 22))],
             [0, 0.5, 1].map { YugongArt.boyLayer(.carry, fill: $0, grid: 22) }),
        ]
        for (i, row) in rows.enumerated() {
            let y = 180 + CGFloat(i) * 420
            text(row.0, 60, y, 34, .bold)
            text(row.1, 60, y + 48, 19, .regular, NSColor(white: 0.35, alpha: 1), width: 1880)
            for (j, p) in row.2.enumerated() {
                let x = 60 + CGFloat(j) * 290
                card(p.1, x, y + 90, 272)
                text(p.0, x + 8, y + 368, 18, .semibold)
            }
            text("meter 0 / 50 / 100%", 1240, y + 90, 18, .semibold)
            for (j, img) in row.3.enumerated() { card(img, 1240 + CGFloat(j) * 230, y + 120, 210) }
        }

        // the household in the popover scene (mock: positions to be used when they are animated)
        let y0: CGFloat = 1040
        text("In the scene (mock, 2x)", 60, y0, 26, .bold)
        let sz = CGSize(width: 292, height: 176), cell: CGFloat = 3
        let info = SceneInfo(state: .lively, carrier: 0.5, mountainLeft: 0.7, grandson: 0.4, night: false)
        let bg = YugongArt.scene(info, t: 0.5, size: sz)
        let r = NSRect(x: 60, y: y0 + 44, width: sz.width * 2, height: sz.height * 2)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: r, xRadius: 20, yRadius: 20).addClip()
        bg.draw(in: r)
        let gh = Int(sz.height / cell), ground = gh - 6
        func put(_ img: CGImage?, _ x: Int, _ yCell: Int, _ n: Int) {   // y-down cells inside the flipped page
            YugongArt.crisp(img, size: NSSize(width: n, height: n))
                .draw(in: NSRect(x: r.minX + CGFloat(x) * cell * 2, y: r.minY + CGFloat(yCell) * cell * 2, width: CGFloat(n) * cell * 2, height: CGFloat(n) * cell * 2))
        }
        NSGraphicsContext.current?.imageInterpolation = .none
        put(YugongArt.sonLayer(.raise, fill: 0.6), 12, ground + 2 - 30, 32)
        put(YugongArt.boyLayer(.hop, fill: 0.5, grid: 22), -3, ground + 2 - 21, 22)
        NSGraphicsContext.restoreGraphicsState()
        text("Left to right: the boy hops in with his basket, the son breaks rock at the foot, Grandpa digs, the grandson carries.",
             700, y0 + 60, 19, .regular, ink, width: 1240)
        text("The mock draws the son and the boy over the scene; in the app they stand behind Grandpa.",
             700, y0 + 120, 17, .regular, NSColor(white: 0.45, alpha: 1), width: 1240)
        let sw: [(String, NSColor)] = [("Shirt", FamilyColors.shirt), ("Vest", FamilyColors.vest), ("Trousers", FamilyColors.trousers),
                                       ("Headband", FamilyColors.headband), ("Stone", FamilyColors.stone), ("Boy jacket", FamilyColors.boyJacket),
                                       ("Boy trousers", FamilyColors.boyTrousers)] + FamilyColors.sleeve.enumerated().map { ("색동 \($0.offset + 1)", $0.element) }
        for (i, (name, col)) in sw.enumerated() {
            let x = 700 + CGFloat(i % 6) * 210, y = y0 + 190 + CGFloat(i / 6) * 90
            col.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 190, height: 44), xRadius: 8, yRadius: 8).fill()
            NSColor(white: 0, alpha: 0.15).setStroke(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 190, height: 44), xRadius: 8, yRadius: 8).stroke()
            text(name, x, y + 46, 14)
        }
    }
}
