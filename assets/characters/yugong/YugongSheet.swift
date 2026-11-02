import AppKit

// Character sheet: large reference drawings of Grandpa Yugong for review. Not used by the app UI;
// rendered by the YugongSheet tool.

public enum YugongSheet {
    struct Named { let en: String; let ko: String; let pose: YPose; let k: CGFloat }

    static var keyPoses: [Named] {
        let d = YugongRig.dig(depth: 0, tired: false)
        var wipe = YugongRig.wipeSweat(0); wipe.sweat = true
        return [
            Named(en: "Wind-up (anticipation)", ko: "삽 들기 · 예비동작", pose: d[0], k: 0),
            Named(en: "Thrust", ko: "푹 찌르기", pose: d[1], k: 0),
            Named(en: "Toss into the carrier", ko: "지게로 휙", pose: d[3], k: 0.45),
            Named(en: "Chatting with the magpie", ko: "까치랑 수다", pose: YugongRig.leanOnShovel(talk: true), k: 0.5),
            Named(en: "Wiping sweat", ko: "땀 닦기", pose: wipe, k: 0),
            Named(en: "Stretching his back", ko: "허리 펴기", pose: YugongRig.backStretch(), k: 0),
            Named(en: "Carrier full: resting", ko: "지게 가득 · 쉬는 중", pose: YugongRig.rest(false), k: 0.4),
            Named(en: "Morning stretch (reset)", ko: "아침 기지개 · 리셋", pose: YugongRig.morning(0), k: 0.3),
            Named(en: "Night yawn", ko: "밤 하품", pose: YugongRig.yawn(), k: 0),
        ]
    }

    static var expressions: [Named] {
        func e(_ en: String, _ ko: String, _ eyes: Eyes, _ mouth: Mouth, sweat: Bool = false, tip: CGFloat = 0, back: Bool = false) -> Named {
            var p = YPose(); p.eyes = eyes; p.mouth = mouth; p.sweat = sweat; p.hatTip = tip; p.lookBack = back
            return Named(en: en, ko: ko, pose: p, k: 0)
        }
        return [
            e("Content", "흐뭇", .open, .smile),
            e("Delighted", "신남", .happy, .open),
            e("Heave-ho!", "영차!", .squeeze, .open, sweat: true),
            e("Huff, puff", "헥헥", .closed, .open, sweat: true),
            e("Chatty", "수다", .open, .open, back: true),
            e("Yawn", "하품", .closed, .yawn),
            e("Napping", "쿨쿨", .closed, .snore, tip: 1),
            e("Proud", "뿌듯", .happy, .smile),
        ]
    }

    // MARK: - single drawings

    /// One side-view pose in a `cell` square: a `grid`-pixel sprite scaled up.
    static func poseImage(_ p: YPose, k: CGFloat, fill: CGFloat, cell: CGFloat, grid: Int = 40,
                          menuBar: Bool = false, bird: Bool = true) -> NSImage {
        YugongArt.crisp(YugongArt.pixelFigure(p, k: k, fill: fill, grid: grid, menuBar: menuBar, bird: bird),
                        size: NSSize(width: cell, height: cell))
    }

    static func turnImage(front: Bool, cell: CGFloat) -> NSImage {
        let n = 40
        let cg = YugongArt.pixelLayer(n, n, { c in
            c.scaleBy(x: CGFloat(n) / 100, y: CGFloat(n) / 100)
            drawTurn(Pen(c: c, mb: false, pal: .pixel, ppu: CGFloat(n) / 100), front: front)
        }, after: { c in
            PixelHeads.stampTurn(c, front: front, center: CGPoint(x: 50, y: 33), grid: n)
            PixelHeads.magpie(c, at: CGPoint(x: 30, y: 13), .perch, k: 0, grid: n, faceRight: true)
        })
        return YugongArt.crisp(cg, size: NSSize(width: cell, height: cell))
    }

    static func headImage(_ p: YPose, cell: CGFloat) -> NSImage {
        let n = 24
        let cg = YugongArt.pixelLayer(n, n, { _ in }, after: { c in
            PixelHeads.stamp(c, pose: p, at: YugongArt.HeadSpot(center: CGPoint(x: 52, y: 46), mirror: p.lookBack), grid: n, small: false)
            if p.sweat {
                c.setFillColor(Palette.pixel.sweat.cgColor)
                c.fill(CGRect(x: 1, y: 9, width: 1, height: 2)); c.fill(CGRect(x: 21, y: 10, width: 1, height: 2))
            }
            if p.mouth == .snore {
                c.setFillColor(Palette.pixel.birdBlue.cgColor)
                for (x, y) in [(2, 1), (3, 1), (4, 1), (3, 2), (2, 3), (3, 3), (4, 3)] { c.fill(CGRect(x: x, y: y, width: 1, height: 1)) }
            }
        })
        return YugongArt.crisp(cg, size: NSSize(width: cell, height: cell))
    }

    // MARK: - front and back views (turnaround)

    static func drawTurn(_ pn: Pen, front: Bool) {
        let pal = pn.pal
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        func jige(_ onTop: Bool) {
            if !onTop {   // from the front only the pole tops and the basket edges show
                pn.shape(pn.path([P(29, 42), P(71, 42), P(68, 66), P(32, 66)], closed: true), pal.hat, edge: false)
                pn.tube([P(31, 14), P(33, 84)], 3.4, pal.wood, edge: false)
                pn.tube([P(69, 14), P(67, 84)], 3.4, pal.wood, edge: false)
                return
            }
            pn.tube([P(31, 14), P(34, 88)], 3.6, pal.wood, edge: false)
            pn.tube([P(69, 14), P(66, 88)], 3.6, pal.wood, edge: false)
            pn.tube([P(32, 76), P(68, 76)], 3, pal.woodDark, edge: false)
            let m = CGMutablePath()
            m.move(to: P(31, 45)); m.addQuadCurve(to: P(69, 45), control: P(50, 26)); m.closeSubpath()
            pn.shape(m, pal.earth, edge: false)
            pn.dot(P(44, 40), pal.earthDark); pn.dot(P(55, 41), pal.earthDark)
            let basket = pn.path([P(29, 45), P(71, 45), P(66, 72), P(34, 72)], closed: true)
            pn.shape(basket, pal.hat, edge: false)
            for y: CGFloat in [52, 59, 66] { pn.line([P(31 + (y - 45) * 0.18, y), P(69 - (y - 45) * 0.18, y)], pal.hatDark) }
            pn.tube([P(31, 24), P(69, 24)], 2.6, pal.woodDark, edge: false)
        }
        if front { jige(false) }
        // legs and straw sandals
        pn.tube([P(44, 72), P(43, 91)], 10, front ? pal.pants : pal.pantsDark, edge: false)
        pn.tube([P(56, 72), P(57, 91)], 10, front ? pal.pants : pal.pantsDark, edge: false)
        pn.ellipse(P(42, 93.5), 11, 4.5, pal.wood, edge: false)
        pn.ellipse(P(58, 93.5), 11, 4.5, pal.wood, edge: false)
        // jacket with the vermilion sash
        pn.shape(pn.path([P(37, 45), P(63, 45), P(67, 77), P(33, 77)], closed: true), pal.jacket, edge: false)
        pn.shape(pn.path([P(34.6, 66), P(65.4, 66), P(65.9, 70.5), P(34.1, 70.5)], closed: true), pal.sash, edge: false)
        // shovel in one hand
        let sx: CGFloat = front ? 72 : 28
        pn.tube([P(sx - 4, 42), P(sx + 4, 42)], 2.6, pal.woodDark, edge: false)
        pn.tube([P(sx, 42), P(sx, 84)], 2.8, pal.wood, edge: false)
        pn.shape(pn.path([P(sx - 5, 84), P(sx + 5, 84), P(sx + 4, 91), P(sx, 96), P(sx - 4, 91)], closed: true), pal.iron, edge: false)
        // arms at the sides
        pn.tube([P(38, 48), P(33, 60), P(33, 72)], 7, pal.jacketLight, edge: false)
        pn.tube([P(62, 48), P(67, 60), P(67, 72)], 7, pal.jacketLight, edge: false)
        pn.ellipse(P(33, 74), 6, 6, pal.skin, edge: false)
        pn.ellipse(P(67, 74), 6, 6, pal.skin, edge: false)
        if !front { jige(true) }
    }

    // MARK: - the sheet

    static let personality: [(String, String)] = [
        ("Name", "우공 할아버지 · Grandpa Yugong (愚公), 90 years young"),
        ("Story", "Liezi's \u{201C}Foolish Old Man Who Moved the Mountains\u{201D}: he digs a little every day; one day heaven, moved, carries the mountain away."),
        ("Trait 1 · 우직", "Stubborn-steady: never quits, never hurries. One shovel at a time."),
        ("Trait 2 · 허허", "Laughs things off: a full carrier is just a reason for a nap."),
        ("Trait 3 · 수다", "Chatty: talks to his magpie all day, and brags about his grandson."),
        ("Catchphrase", "\u{201C}한 삽이면 한 삽만큼 줄지, 허허!\u{201D}  (One shovel, one shovel less mountain!)"),
        ("Accent colour", "Vermilion sash: the only strong colour on him. Everything else is straw, indigo and white."),
        ("Companions", "Magpie (까치, bringer of good news) and his grandson (Codex meter)."),
    ]

    static let charmNotes = [
        "Big readable head: head + hat = one third of his height; the hat brim is the widest shape.",
        "Simple shapes: circle head, triangle beard, flat brim, one A-frame carrier.",
        "One strong colour accent (vermilion sash); white beard + straw hat read on light and dark menu bars.",
        "Exaggerated anticipation and squash: crouch before the thrust, stretch on the toss and the morning stretch.",
        "Habits carry personality: chatting, wiping sweat, back stretch, yawning, napping with the hat over his eyes.",
    ]

    static func swatches() -> [(String, NSColor)] {
        let p = Palette.pixel
        return [("Outline", p.outline), ("Skin", p.skin), ("Nose", p.nose), ("Blush", p.blush), ("Beard", p.beard),
                ("Beard shade", p.beardShade), ("Straw hat", p.hat), ("Straw shade", p.hatDark), ("Hat band", p.band),
                ("Jacket", p.jacket), ("Jacket dark", p.jacketDark), ("Sash ★", p.sash), ("Trousers", p.pants),
                ("Wood", p.wood), ("Earth", p.earth), ("Shovel", p.iron), ("Magpie", p.bird), ("Magpie wing", p.birdBlue)]
    }

    /// Popover scenes for every state (plus night and the cutscene), for review.
    public static func sceneStrip() -> NSImage {
        let sz = CGSize(width: 292, height: 176)
        let infos: [(String, SceneInfo, Double)] = [
            ("lively", SceneInfo(state: .lively, carrier: 0.34, mountainLeft: 0.92, grandson: 0.18, night: false), 0.5),
            ("steady", SceneInfo(state: .steady, carrier: 0.6, mountainLeft: 0.7, grandson: 0.4, night: false), 1.3),
            ("straining", SceneInfo(state: .straining, carrier: 0.9, mountainLeft: 0.5, grandson: 0.7, night: false), 0.9),
            ("resting", SceneInfo(state: .resting, carrier: 1.0, mountainLeft: 0.35, grandson: 1.0, night: true), 0.5),
            ("morning", SceneInfo(state: .morning, carrier: 0, mountainLeft: 0.2, grandson: 0.0, night: false), 0.3),
            ("lively-night", SceneInfo(state: .lively, carrier: 0.2, mountainLeft: 0.6, grandson: nil, night: true), 9.6),
            ("cutscene", SceneInfo(state: .morning, carrier: 0, mountainLeft: 0.0, grandson: 0.1, night: false, cutscene: 0.55), 0.3),
        ]
        let cols = 4, gap: CGFloat = 12
        let rows = (infos.count + cols - 1) / cols
        let W = CGFloat(cols) * (sz.width + gap) + gap, H = CGFloat(rows) * (sz.height + 30 + gap) + gap
        return NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in
            NSColor(white: 0.95, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
            for (i, (name, info, t)) in infos.enumerated() {
                let x = gap + CGFloat(i % cols) * (sz.width + gap), y = gap + CGFloat(i / cols) * (sz.height + 30 + gap)
                let img = YugongArt.scene(info, t: t, size: sz)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: sz.width, height: sz.height), xRadius: 14, yRadius: 14).addClip()
                img.draw(in: NSRect(x: x, y: y, width: sz.width, height: sz.height))
                NSGraphicsContext.restoreGraphicsState()
                (name as NSString).draw(at: NSPoint(x: x + 4, y: y + sz.height + 6), withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)])
            }
            return true
        }
    }

    /// Frames of one state's routine, left to right, `fps` per second (pixel at 4x).
    public static func frames(_ st: PetState, fps: Double, night: Bool = false) -> NSImage {
        let n = Int((YugongRig.period(st, night: night) * fps).rounded())
        let cols = 12, cell: CGFloat = 160
        let rows = (n + cols - 1) / cols
        return NSImage(size: NSSize(width: CGFloat(cols) * cell, height: CGFloat(rows) * cell), flipped: true) { _ in
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: CGFloat(cols) * cell, height: CGFloat(rows) * cell).fill()
            for i in 0..<n {
                let img = YugongArt.figure(st, t: Double(i) / fps, carrier: 0.5, night: night, size: 120, menuBar: false)
                NSGraphicsContext.current?.imageInterpolation = .none
                img.draw(in: NSRect(x: CGFloat(i % cols) * cell, y: CGFloat(i / cols) * cell, width: cell, height: cell))
            }
            return true
        }
    }

    public static let pageSize = NSSize(width: 2400, height: 2700)

    /// Draws the whole sheet into the current (flipped) graphics context.
    public static func drawSheet() {
        let W = pageSize.width
        NSColor.white.setFill(); NSRect(origin: .zero, size: pageSize).fill()
        let ink = NSColor(srgbRed: 0x26 / 255.0, green: 0x21 / 255.0, blue: 0x1D / 255.0, alpha: 1)   // text colour
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ w: NSFont.Weight = .regular,
                  _ col: NSColor = ink, width: CGFloat = 0) {
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: w), .foregroundColor: col]
            if width > 0 { (s as NSString).draw(in: NSRect(x: x, y: y, width: width, height: 400), withAttributes: a) }
            else { (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: a) }
        }
        func section(_ title: String, _ y: CGFloat) {
            text(title, 60, y, 30, .bold)
            NSColor(white: 0.8, alpha: 1).setFill(); NSRect(x: 60, y: y + 44, width: W - 120, height: 2).fill()
        }
        text("우공 할아버지  Grandpa Yugong", 60, 40, 64, .heavy)
        text("Character sheet — pixel art (픽셀)", 60, 120, 30, .medium, NSColor(white: 0.35, alpha: 1))
        text("Sprite grid 40 px (popover) and 20 px (menu bar). Turnaround and poses at 12x / 6x, expressions at 11x.",
             60, 162, 22, .regular, NSColor(white: 0.45, alpha: 1))

        // 1. turnaround + personality card
        section("Turnaround  ·  앞 / 옆 / 뒤", 220)
        let tc: CGFloat = 480
        for (i, (label, img)) in [("Front", turnImage(front: true, cell: tc)),
                                  ("Side (3/4)", poseImage(YugongRig.stand, k: 0, fill: 0.5, cell: tc)),
                                  ("Back", turnImage(front: false, cell: tc))].enumerated() {
            let x = 60 + CGFloat(i) * (tc + 30)
            NSColor(white: 0, alpha: 0.04).setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: 290, width: tc, height: tc), xRadius: 16, yRadius: 16).fill()
            img.draw(in: NSRect(x: x, y: 290, width: tc, height: tc))
            text(label, x + 16, 290 + tc + 8, 22, .semibold)
        }
        let cardX: CGFloat = 60 + 3 * (tc + 30) + 10, cardW = W - cardX - 60
        NSColor(srgbRed: 0.79, green: 0.28, blue: 0.23, alpha: 0.08).setFill()
        NSBezierPath(roundedRect: NSRect(x: cardX, y: 290, width: cardW, height: 560), xRadius: 20, yRadius: 20).fill()
        text("Personality card", cardX + 24, 306, 28, .bold, NSColor(srgbRed: 0xC0 / 255.0, green: 0x47 / 255.0, blue: 0x3A / 255.0, alpha: 1))
        var cy: CGFloat = 352
        for (k, v) in personality {
            text(k, cardX + 24, cy, 17, .bold)
            text(v, cardX + 24, cy + 22, 17, .regular, ink, width: cardW - 48)
            cy += v.count > 70 ? 76 : 54
        }

        // 2. expressions
        section("Expressions  ·  표정", 880)
        let ec: CGFloat = 264
        for (i, e) in expressions.enumerated() {
            let x = 60 + CGFloat(i) * (ec + 16)
            NSColor(white: 0, alpha: 0.04).setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: 950, width: ec, height: ec), xRadius: 14, yRadius: 14).fill()
            headImage(e.pose, cell: ec).draw(in: NSRect(x: x, y: 950, width: ec, height: ec))
            text("\(e.ko)  \(e.en)", x + 10, 950 + ec + 6, 19, .semibold)
        }

        // 3. key poses with habits
        section("Key poses and habits  ·  동작과 버릇", 1290)
        let pc: CGFloat = 248
        for (i, n) in keyPoses.enumerated() {
            let x = 60 + CGFloat(i) * (pc + 10)
            NSColor(white: 0, alpha: 0.04).setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: 1360, width: pc, height: pc), xRadius: 14, yRadius: 14).fill()
            poseImage(n.pose, k: n.k, fill: n.pose.jigeOnBack ? 0.55 : 1, cell: pc).draw(in: NSRect(x: x, y: 1360, width: pc, height: pc))
            text(n.ko, x + 8, 1360 + pc + 6, 19, .bold)
            text(n.en, x + 8, 1360 + pc + 32, 16, .regular, NSColor(white: 0.4, alpha: 1))
        }

        // 4. carrier = the 5-hour meter
        section("The carrier is the 5-hour meter  ·  지게 = 5시간 사용량", 1700)
        for (i, f) in [0.0, 0.35, 0.7, 1.0].enumerated() {
            let x = 60 + CGFloat(i) * 270
            poseImage(YugongRig.stand, k: 0, fill: CGFloat(f), cell: 240, bird: false).draw(in: NSRect(x: x, y: 1770, width: 240, height: 240))
            text("\(Int(f * 100))%", x + 100, 2014, 22, .bold)
        }
        text("Earth heaps up in the basket as the 5-hour window fills. At 100% he sets the carrier down and naps until the reset time.",
             1160, 1800, 20, .regular, ink, width: 1180)

        // 5. palette
        section("Palette  ·  색", 2070)
        for (i, (name, col)) in swatches().enumerated() {
            let x = 60 + CGFloat(i % 9) * 150, y = 2130 + CGFloat(i / 9) * 110
            col.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 130, height: 56), xRadius: 8, yRadius: 8).fill()
            NSColor(white: 0, alpha: 0.15).setStroke(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 130, height: 56), xRadius: 8, yRadius: 8).stroke()
            let c = col.usingColorSpace(.sRGB)!
            let hex = String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
            text("\(name)\n\(hex)", x, y + 58, 13, name.hasPrefix("Sash") ? .bold : .regular)
        }

        // 6. silhouette test at actual size
        let sx: CGFloat = 1440
        text("Silhouette + menu-bar test (actual pixels, then 4x)", sx, 2100, 22, .bold)
        let tests: [(PetState, Double)] = [(.lively, 0.1), (.lively, 1.15), (.straining, 0.2), (.resting, 0.5), (.morning, 0.3)]
        for (row, bg) in [NSColor(white: 0.93, alpha: 1), NSColor(white: 0.17, alpha: 1)].enumerated() {
            let y = 2140 + CGFloat(row) * 40
            bg.setFill(); NSRect(x: sx, y: y, width: 900, height: 30).fill()
            var x = sx + 10
            for size in [18, 20, 22] {
                for (st, t) in tests.prefix(3) {
                    YugongArt.figure(st, t: t, carrier: 0.5, night: false, size: CGFloat(size), menuBar: true)
                        .draw(in: NSRect(x: x, y: y + 15 - CGFloat(size) / 2, width: CGFloat(size), height: CGFloat(size)))
                    x += CGFloat(size) + 8
                }
                x += 30
            }
            text(row == 0 ? "light bar" : "dark bar", x + 10, y + 4, 15, .regular, row == 0 ? ink : .white)
        }
        // black silhouettes and 4x
        var x = sx
        for (st, t) in tests {
            let img = YugongArt.figure(st, t: t, carrier: 0.5, night: false, size: 20, menuBar: true)
            let sil = NSImage(size: img.size, flipped: false) { r in
                img.draw(in: r); NSColor.black.setFill(); r.fill(using: .sourceAtop); return true
            }
            sil.draw(in: NSRect(x: x, y: 2240, width: 20, height: 20))
            NSGraphicsContext.current?.imageInterpolation = .none
            img.draw(in: NSRect(x: x, y: 2270, width: 80, height: 80))
            sil.draw(in: NSRect(x: x + 90, y: 2270, width: 80, height: 80))
            x += 180
        }

        // 7. charm notes
        section("Why he should feel charming  ·  매력 포인트", 2400)
        for (i, n) in charmNotes.enumerated() { text("• " + n, 60, 2460 + CGFloat(i) * 34, 20) }
        text("Original design for TokenPet from the public-domain Liezi tale. Drawn as code; no AI image generation, tracing or third-party art.",
             60, 2640, 16, .regular, NSColor(white: 0.5, alpha: 1))
    }
}
