import AppKit

// Three more from the Liezi tale (愚公移山), in the same pixel art as the household:
//   Yugong's wife   - "his wife raised a doubt" (其妻獻疑): where will the earth and stones go?
//   Zhisou (智叟)    - the clever old man of the river bend, who laughs at him (笑而止之)
//   Kua'e's two sons - the giants the Heavenly Emperor sends to carry the mountains away on their backs (命夸娥氏二子負二山)
// Bodies are shapes in figure units (0...100, y down) rasterized on a small grid with the outline
// pass; the heads are placed by hand, one character per pixel.

private func hex(_ h: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: 1)
}

enum VisitorColors {
    static let jacket = hex(0xF4EEE0), skirt = hex(0x5B4A8A), ribbon = hex(0xC9483A), hair = hex(0xB9B4AC), pin = hex(0xE0B040)
    static let robe = hex(0x9DB7A8), robeDark = hex(0x6F8C7C), fan = hex(0xF2E3B3)
    static let giantSkin = hex(0xD9965F), giantShade = hex(0xB87645), scarf = hex(0xFAF7EF)
    /// the elder son in blue, the younger in red: (headband and sash, trousers)
    static let brothers: [(band: NSColor, pants: NSColor)] = [(hex(0x3E6FC9), hex(0x2F4A80)), (hex(0xD0453A), hex(0x8A2E2A))]
}

/// The wife: hands on her hips, then asking (doubting); arms up, then clapping (cheering).
public enum WifePose: CaseIterable { case hips, ask, cheer, clap }
/// Zhisou: laughing with a hand on his belly, then pointing his fan.
public enum ZhisouPose: CaseIterable { case laugh, point }
/// Kua'e's sons: arms up under the mountain, legs straight or striding.
public enum GiantPose: CaseIterable { case lift, strideA, strideB }

enum VisitorHeads {
    static func colors(band: NSColor = VisitorColors.brothers[0].band) -> [Character: NSColor] {
        let p = Palette.pixel
        return ["o": p.outline, "k": p.kidHair, "s": p.skin, "p": p.blush, "m": p.mouth, "r": p.nose, "w": p.beard,
                "g": VisitorColors.hair, "y": VisitorColors.pin, "t": VisitorColors.giantSkin, "b": band]
    }
    /// The wife, looking left (mirrored to face Grandpa): grey hair in a bun with a gold pin (비녀).
    static let wife: [String] = [
        "....oooo.....",
        "...oggggo.oo.",
        "..oggggggoggo",
        ".oggggggggggo",
        "oggggggggyyyo",
        "ogsggggggggo.",
        "ossssssgggo..",
        "oskssskssgo..",
        "osssssssggo..",
        "opssssspsgo..",
        ".osmmsssso...",
        "..oooooo.....",
    ]
    static let wifeAnchor = (x: 6, y: 6)
    /// Zhisou, looking left (mirrored): bald with a white topknot, white brows, a smug squint, a long thin beard.
    static let zhisou: [String] = [
        ".....ooo.....",
        "....owwwo....",
        "...ooooooo...",
        "..osssssssso.",
        ".osssssssssso",
        ".owwsssswwwso",
        ".okksssskksso",
        "orsssssssssso",
        ".owwwwssssswo",
        "..owmmwssswo.",
        "..owwwwwwwo..",
        "...owwwwwo...",
        "...owwwwo....",
        "....owwo.....",
        "....owo......",
        ".....o.......",
    ]
    static let zhisouAnchor = (x: 6, y: 6)
    /// A son of Kua'e, facing us: topknot, headband in his colour, ruddy cheeks, a broad smile.
    static let giant: [String] = [
        "....ooo....",
        "...okkko...",
        "..okkkkko..",
        ".okkkkkkko.",
        "obbbbbbbbbo",
        "ottttttttto",
        "ottkttttkto",
        "otttttrttto",
        "optttttttpo",
        "otttmmmttto",
        ".ottttttto.",
        "..ooooooo..",
    ]
    static let giantAnchor = (x: 5, y: 6)
}

extension YugongArt {
    // MARK: - the wife

    /// Draws the wife's body facing right; returns where her head goes (canvas units).
    static func wife(_ pn: Pen, _ pose: WifePose) -> CGPoint {
        let V = VisitorColors.self, skin = pn.pal.skin
        let lift: CGFloat = pose == .cheer ? -5 : 0
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y + lift) }
        pn.shape(pn.path([P(38, 62), P(60, 62), P(70, 94), P(30, 94)], closed: true), V.skirt, edge: false)
        pn.shape(pn.path([P(36, 50), P(60, 50), P(63, 66), P(34, 66)], closed: true), V.jacket, edge: false)
        pn.tube([P(52, 56), P(58, 66)], 3, V.ribbon, edge: false)                                   // the 고름 ribbon
        func arm(_ pts: [CGPoint], hand: Bool = true) {
            pn.tube(pts, 6, V.jacket, edge: false)
            if hand, let h = pts.last { pn.ellipse(h, 6, 6, skin, edge: false) }
        }
        switch pose {
        case .hips: arm([P(38, 54), P(28, 62), P(36, 66)], hand: false); arm([P(58, 54), P(68, 62), P(60, 66)], hand: false)
        case .ask: arm([P(38, 54), P(28, 62), P(36, 66)], hand: false); arm([P(58, 54), P(70, 58), P(82, 54)])
        case .cheer: arm([P(38, 54), P(30, 42), P(26, 30)]); arm([P(58, 54), P(66, 42), P(70, 30)])
        case .clap: arm([P(38, 54), P(42, 64), P(50, 58)]); arm([P(58, 54), P(58, 64), P(50, 58)])
        }
        return P(48, 32)
    }

    /// Doubting: hands on hips, then asks (1.8 s loop). Cheering: arms up, clap (0.7 s loop).
    static func wifePose(_ t: Double, cheering: Bool) -> WifePose {
        let period = cheering ? 0.7 : 1.8
        var p = t.truncatingRemainder(dividingBy: period); if p < 0 { p += period }
        return cheering ? (p < 0.35 ? .cheer : .clap) : (p < 1.0 ? .hips : .ask)
    }

    public static func wifeLayer(_ pose: WifePose, grid n: Int = 26) -> CGImage? {
        var head = CGPoint.zero
        return pixelLayer(n, n, { c in
            c.scaleBy(x: CGFloat(n) / 100, y: CGFloat(n) / 100)
            head = wife(Pen(c: c, mb: true, pal: .pixel, ppu: CGFloat(n) / 100), pose)
        }, after: { c in
            var rows = VisitorHeads.wife.map { Array($0) }
            switch pose {
            case .hips, .ask: rows[5][6] = "k"; rows[10][4] = "s"                                    // one brow up, a pursed mouth
            case .cheer, .clap: rows[7][2] = "s"; rows[7][6] = "s"; rows[6][2] = "k"; rows[6][6] = "k"; rows[10][5] = "m"   // happy eyes, open mouth
            }
            FamilyHeads.stamp(c, rows, anchor: VisitorHeads.wifeAnchor, at: head, grid: n, mirror: true, colors: VisitorHeads.colors())
        })
    }

    // MARK: - Zhisou

    /// Draws Zhisou facing right, leaning on his cane; returns where his head goes.
    static func zhisou(_ pn: Pen, _ pose: ZhisouPose) -> CGPoint {
        let V = VisitorColors.self, pal = pn.pal
        let bob: CGFloat = pose == .laugh ? 1.5 : 0
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y + bob) }
        pn.tube([P(28, 60), CGPoint(x: 24, y: 94)], 3, pal.wood, edge: false)                        // the cane
        pn.shape(pn.path([P(38, 46), P(60, 46), P(68, 94), P(32, 94)], closed: true), V.robe, edge: false)
        pn.tube([P(50, 66), P(51, 93)], 2, V.robeDark, edge: false)
        pn.tube([P(37, 64), P(63, 64)], 3, V.robeDark, edge: false)                                   // the sash
        pn.tube([P(40, 48), P(32, 56), P(28, 60)], 7, V.robe, edge: false)                            // hand on the cane
        pn.ellipse(P(28, 60), 6, 6, pal.skin, edge: false)
        switch pose {
        case .laugh:
            pn.tube([P(58, 48), P(66, 58), P(58, 64)], 7, V.robe, edge: false)                       // hand on his belly
            pn.ellipse(P(58, 64), 6, 6, pal.skin, edge: false)
            return P(48, 24)
        case .point:
            pn.tube([P(58, 48), P(70, 50), P(80, 44)], 7, V.robe, edge: false)
            pn.shape(pn.path([P(80, 44), P(90, 30), P(96, 40)], closed: true), V.fan, edge: false)   // the fan, pointing
            pn.ellipse(P(80, 44), 6, 6, pal.skin, edge: false)
            return P(48, 26)
        }
    }

    /// Laughs for 0.6 s, points for 1 s.
    static func zhisouPose(_ t: Double) -> ZhisouPose {
        var p = t.truncatingRemainder(dividingBy: 1.6); if p < 0 { p += 1.6 }
        return p < 0.6 ? .laugh : .point
    }

    public static func zhisouLayer(_ pose: ZhisouPose, grid n: Int = 30) -> CGImage? {
        var head = CGPoint.zero
        return pixelLayer(n, n, { c in
            c.scaleBy(x: CGFloat(n) / 100, y: CGFloat(n) / 100)
            head = zhisou(Pen(c: c, mb: true, pal: .pixel, ppu: CGFloat(n) / 100), pose)
        }, after: { c in
            var rows = VisitorHeads.zhisou.map { Array($0) }
            if pose == .laugh { rows[9][6] = "m"; rows[10][4] = "m"; rows[10][5] = "m" }             // "heo heo!"
            FamilyHeads.stamp(c, rows, anchor: VisitorHeads.zhisouAnchor, at: head, grid: n, mirror: true, colors: VisitorHeads.colors())
        })
    }

    // MARK: - Kua'e's two sons

    /// A giant facing us, arms raised to hold the mountain above his head.
    static func giant(_ pn: Pen, _ pose: GiantPose, brother b: Int) {
        let V = VisitorColors.self, col = V.brothers[b % 2]
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        let legs: [(CGPoint, CGPoint)] = switch pose {
        case .lift: [(P(42, 66), P(40, 94)), (P(58, 66), P(60, 94))]
        case .strideA: [(P(42, 66), P(32, 94)), (P(58, 66), P(66, 91))]
        case .strideB: [(P(42, 66), P(45, 91)), (P(58, 66), P(56, 94))]
        }
        for (a, z) in legs { pn.tube([a, z], 12, col.pants, edge: false) }
        pn.tube([P(32, 40), P(18, 52), P(22, 66)], 4, V.scarf, edge: false)                          // the heavenly scarf
        pn.tube([P(68, 40), P(82, 52), P(78, 66)], 4, V.scarf, edge: false)
        pn.shape(pn.path([P(32, 36), P(68, 36), P(64, 68), P(36, 68)], closed: true), V.giantSkin, edge: false)
        pn.tube([P(50, 44), P(50, 56)], 2, V.giantShade, edge: false)
        pn.tube([P(35, 64), P(65, 64)], 5, col.band, edge: false)                                     // sash
        pn.tube([P(36, 40), P(28, 24), P(26, 10)], 10, V.giantSkin, edge: false)
        pn.tube([P(64, 40), P(72, 24), P(74, 10)], 10, V.giantSkin, edge: false)
        pn.ellipse(P(26, 8), 13, 8, V.giantSkin, edge: false); pn.ellipse(P(74, 8), 13, 8, V.giantSkin, edge: false)   // palms up at the top (row 1)
    }

    /// The milestone cutscene, c = 0...1: the sons rise out of the earth with the mountain on their hands
    /// (0.1...0.4), then stride off to the left carrying it (0.4...1). `lift` and `dx` are in scene cells.
    static func cutsceneMotion(_ c: Double, width w: Int) -> (lift: CGFloat, dx: CGFloat, pose: GiantPose) {
        let rise = CGFloat(min(1, max(0, (c - 0.1) / 0.3)))
        let walk = CGFloat(min(1, max(0, (c - 0.4) / 0.6)))
        let pose: GiantPose = walk <= 0 ? .lift : Int(c / 0.07) % 2 == 0 ? .strideA : .strideB
        return (31 * rise, -floor(walk * CGFloat(w) * 0.8), pose)
    }

    public static func giantLayer(_ pose: GiantPose, brother b: Int, grid n: Int = 36) -> CGImage? {
        pixelLayer(n, n, { c in
            c.scaleBy(x: CGFloat(n) / 100, y: CGFloat(n) / 100)
            giant(Pen(c: c, mb: true, pal: .pixel, ppu: CGFloat(n) / 100), pose, brother: b)
        }, after: { c in
            FamilyHeads.stamp(c, VisitorHeads.giant.map { Array($0) }, anchor: VisitorHeads.giantAnchor, at: CGPoint(x: 50, y: 22),
                              grid: n, mirror: false, colors: VisitorHeads.colors(band: VisitorColors.brothers[b % 2].band))
        })
    }

    /// The visitor's layer and its size in cells (feet on the ground at the left of the scene).
    static func visitorLayer(_ v: Visitor, t: Double) -> (CGImage?, Int) {
        switch v {
        case .wifeDoubting: return (wifeLayer(wifePose(t, cheering: false)), 26)
        case .wifeCheering: return (wifeLayer(wifePose(t, cheering: true)), 26)
        case .zhisou: return (zhisouLayer(zhisouPose(t)), 30)
        }
    }
}

// MARK: - the visitors' sheet (review before animating)

extension YugongSheet {
    public static let visitorsSize = NSSize(width: 2000, height: 1700)

    /// The wife, Zhisou and Kua'e's two sons: every pose at 8x, the cutscene frame by frame, and their colours.
    public static func drawVisitorSheet() {
        NSColor.white.setFill(); NSRect(origin: .zero, size: visitorsSize).fill()
        let ink = NSColor(srgbRed: 0x26 / 255.0, green: 0x21 / 255.0, blue: 0x1D / 255.0, alpha: 1)
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ w: NSFont.Weight = .regular,
                  _ col: NSColor = ink, width: CGFloat = 0) {
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: w), .foregroundColor: col]
            if width > 0 { (s as NSString).draw(in: NSRect(x: x, y: y, width: width, height: 300), withAttributes: a) }
            else { (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: a) }
        }
        func card(_ img: CGImage?, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat) {
            NSColor(white: 0, alpha: 0.04).setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: s, height: s), xRadius: 12, yRadius: 12).fill()
            NSGraphicsContext.current?.imageInterpolation = .none
            YugongArt.crisp(img, size: NSSize(width: s, height: s)).draw(in: NSRect(x: x, y: y, width: s, height: s))
        }
        text("우공 이야기의 사람들  The rest of the tale", 60, 40, 56, .heavy)
        text("Character sheet — three new parts from the Liezi, pixel art. They come and go with what happens to your limits.",
             60, 112, 24, .regular, NSColor(white: 0.4, alpha: 1))
        let rows: [(String, String, [(String, CGImage?)])] = [
            ("할머니 (우공의 아내)  Yugong's wife", "\u{201C}His wife raised a doubt\u{201D} (其妻獻疑): where will the earth go? Comes when the plan or the family changes and at a new week; cheers once half the mountain is gone.",
             [("허리 짚기 hips", YugongArt.wifeLayer(.hips)), ("묻기 ask", YugongArt.wifeLayer(.ask)),
              ("만세 cheer", YugongArt.wifeLayer(.cheer)), ("박수 clap", YugongArt.wifeLayer(.clap))]),
            ("지수 영감  Zhisou", "The clever old man of the river bend who laughed at him (笑而止之). Comes when the limit is used up; Grandpa answers 子子孫孫.",
             [("허허 laugh", YugongArt.zhisouLayer(.laugh)), ("부채질 point", YugongArt.zhisouLayer(.point))]),
            ("과아씨의 두 아들  Kua'e's two sons", "Sent by the Heavenly Emperor to carry the mountains away on their backs (負二山). The milestone cutscene.",
             [("형 들기 lift", YugongArt.giantLayer(.lift, brother: 0)), ("형 걷기 A", YugongArt.giantLayer(.strideA, brother: 0)),
              ("아우 걷기 B", YugongArt.giantLayer(.strideB, brother: 1)), ("아우 들기 lift", YugongArt.giantLayer(.lift, brother: 1))]),
        ]
        for (i, row) in rows.enumerated() {
            let y = 170 + CGFloat(i) * 360
            text(row.0, 60, y, 32, .bold)
            text(row.1, 60, y + 44, 18, .regular, NSColor(white: 0.35, alpha: 1), width: 1880)
            for (j, p) in row.2.enumerated() {
                let x = 60 + CGFloat(j) * 250
                card(p.1, x, y + 76, 230)
                text(p.0, x + 8, y + 310, 17, .semibold)
            }
        }
        // in the scene: the two visits, then the cutscene frame by frame
        let sz = CGSize(width: 292, height: 176)
        func scene(_ info: SceneInfo, _ t: Double, _ x: CGFloat, _ y: CGFloat, _ label: String) {
            let r = NSRect(x: x, y: y, width: sz.width, height: sz.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).addClip()
            YugongArt.scene(info, t: t, size: sz).draw(in: r)
            NSGraphicsContext.restoreGraphicsState()
            text(label, x + 4, y + sz.height + 4, 15, .semibold)
        }
        let y0: CGFloat = 1310
        var wife = SceneInfo(state: .morning, carrier: 0, mountainLeft: 0.8, grandson: 0.1, night: false); wife.visitor = .wifeDoubting
        var mock = SceneInfo(state: .resting, carrier: 1, mountainLeft: 0.6, grandson: 0.5, night: true); mock.visitor = .zhisou
        text("In the scene", 1080, 170 + 360 + 76, 22, .bold)
        scene(wife, 0.2, 1080, 170 + 360 + 110, "new week: the wife")
        scene(mock, 0.2, 1400, 170 + 360 + 110, "limit used up: Zhisou")
        text("Milestone cutscene (Kua'e's sons carry the mountain off)", 60, y0 - 40, 22, .bold)
        for (i, c) in [0.05, 0.25, 0.42, 0.62, 0.85].enumerated() {
            scene(SceneInfo(state: .morning, carrier: 0, mountainLeft: 0, grandson: 0.1, night: false, cutscene: c), 0.3,
                  60 + CGFloat(i) * 310, y0, "c = \(c)")
        }
        let sw: [(String, NSColor)] = [("Jacket", VisitorColors.jacket), ("Skirt", VisitorColors.skirt), ("Hair", VisitorColors.hair),
                                       ("Pin", VisitorColors.pin), ("Robe", VisitorColors.robe), ("Fan", VisitorColors.fan),
                                       ("Giant skin", VisitorColors.giantSkin), ("Elder", VisitorColors.brothers[0].band), ("Younger", VisitorColors.brothers[1].band)]
        for (i, (name, col)) in sw.enumerated() {
            let x = 1080 + CGFloat(i % 5) * 180, y = 170 + 720 + 90 + CGFloat(i / 5) * 80
            col.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 160, height: 40), xRadius: 8, yRadius: 8).fill()
            NSColor(white: 0, alpha: 0.15).setStroke(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 160, height: 40), xRadius: 8, yRadius: 8).stroke()
            text(name, x, y + 42, 14)
        }
    }
}
