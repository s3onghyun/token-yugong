import AppKit

// Title rewards (LOGIC.md "Title rewards"): every title adds one thing to the picture and it stays.
//   #1 iron-bladed shovel (wooden before)  #2 teal tassel on the carrier  #3 pickaxe + broken stones
//   #4 two baskets (삼태기)  #5 the Bohai Sea with the dumped earth  #6 terraced fields on the carved slope
//   #7 the family's thatched house  #8 the family banner (농기)  #9 auspicious clouds
//   #10 golden shovel, an open road with a milestone, and once, the finale (both mountains carried off)
// The menu bar shows only #1, #2, #3, #8 and #10. Grandpa's face, hat and clothes never change.

private func hx(_ h: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: 1)
}

enum RewardColors {
    static let gold = hx(0xE0B040), teal = hx(0x4DB884), cream = hx(0xF4EEE0), road = hx(0xF2E3B3)
    static let edge = NSColor(srgbRed: 0.16, green: 0.2, blue: 0.18, alpha: 1)
}

// MARK: - gear on Grandpa (figure units, Pen)

enum TitleGear {
    /// #0 a wooden spade, #1 iron (the classic look), #10 golden.
    static func blade(_ pn: Pen) -> NSColor { pn.titles <= 0 ? pn.pal.wood : pn.titles >= 10 ? RewardColors.gold : pn.pal.iron }

    /// The golden blade catches the light (big sizes only).
    static func bladeGlint(_ pn: Pen, base: CGPoint, d: CGPoint, n: CGPoint) {
        guard pn.titles >= 10, !pn.mb else { return }
        pn.dot(CGPoint(x: base.x + d.x * 5 + n.x * 2, y: base.y + d.y * 5 + n.y * 2), pn.pal.birdWhite, pixels: 1)
    }

    /// #3 a pickaxe tucked behind the basket, its iron head showing above the rim.
    static func behindBasket(_ pn: Pen, _ J: (CGFloat, CGFloat) -> CGPoint) {
        guard pn.titles >= 3 else { return }
        let mb = pn.mb
        pn.tube([J(21, -4), J(27, mb ? -40 : -44)], mb ? 3.6 : 2.4, pn.pal.wood)
        pn.tube([J(17, mb ? -38 : -42), J(26, mb ? -43 : -47), J(37, mb ? -40 : -43)], mb ? 4.6 : 2.8, pn.pal.iron)
    }

    /// #2 a teal tassel tied to the near pole; #8 (menu bar only) a white banner above it. In the scene
    /// the banner is planted in the ground instead: the magpie perches on the pole top.
    static func onPoles(_ pn: Pen, _ J: (CGFloat, CGFloat) -> CGPoint) {
        let pal = pn.pal, mb = pn.mb
        if pn.titles >= 8 && mb {
            pn.tube([J(18.5, -52), J(19.5, -64)], 3, pal.woodDark)
            let top: CGFloat = -64, bot: CGFloat = -55
            pn.shape(pn.path([J(19.5, top), J(34, top + 1), J(30, (top + bot) / 2), J(34, bot + 1), J(19.5, bot)], closed: true), pal.birdWhite)
        }
        if pn.titles >= 2 {
            let knot = J(20, mb ? -46 : -45)
            pn.ellipse(knot, mb ? 8 : 4.8, mb ? 8 : 4.8, RewardColors.teal, edge: !mb)
            pn.tube([knot, J(21.5, mb ? -35 : -36)], mb ? 4.6 : 3, RewardColors.teal, edge: !mb)
        }
    }
}

// MARK: - the world around him (backdrop cells, y down)

/// Pixel sprite: one character per cell, "." transparent, optional 1-cell outline around it.
func sprite(_ c: CGContext, _ rows: [String], x ox: Int, y oy: Int, _ col: [Character: NSColor], outline: NSColor? = nil, mirror: Bool = false) {
    let g = rows.map { Array($0) }
    let w = g.first?.count ?? 0, h = g.count
    func at(_ x: Int, _ y: Int) -> Character { (x < 0 || y < 0 || x >= w || y >= h) ? "." : g[y][mirror ? w - 1 - x : x] }
    if let o = outline {
        c.setFillColor(o.cgColor)
        for y in -1...h { for x in -1...w where at(x, y) == "." {
            if at(x - 1, y) != "." || at(x + 1, y) != "." || at(x, y - 1) != "." || at(x, y + 1) != "." {
                c.fill(CGRect(x: ox + x, y: oy + y, width: 1, height: 1))
            }
        } }
    }
    for y in 0..<h { for x in 0..<w { let ch = at(x, y); if ch != ".", let k = col[ch] {
        c.setFillColor(k.cgColor); c.fill(CGRect(x: ox + x, y: oy + y, width: 1, height: 1))
    } } }
}

enum TitleWorld {
    static let p = Palette.pixel

    /// Where people stand (cell columns of their bodies, not their layers), so props can keep clear of them.
    static func occupied(_ info: SceneInfo, w: Int) -> [Range<Int>] {
        var r: [Range<Int>] = [49..<76]                                    // Grandpa and his carrier
        if info.son != nil { r.append(17..<34) }
        if info.boy != nil { r.append(0..<17) }
        if info.grandson != nil { r.append((w - 21)..<(w - 6)) }
        if info.visitor != nil && info.cutscene == nil { r.append(0..<24) }
        return r
    }

    /// Columns of `x..<x+width` that someone stands in.
    static func cover(_ x: Int, _ width: Int, _ taken: [Range<Int>]) -> Int { taken.reduce(0) { $0 + $1.clamped(to: x..<(x + width)).count } }

    /// The first spot in `prefs` (left edges) where `width` columns are clear of everyone; else the least covered one.
    static func clear(_ width: Int, _ prefs: [Int], _ taken: [Range<Int>]) -> Int {
        prefs.min { cover($0, width, taken) < cover($1, width, taken) } ?? prefs[0]   // min keeps the first of equals
    }

    /// Left edges of the props that dodge people. With no room for both baskets, one stands in the gap
    /// between the son and Grandpa; with the whole family out, the house takes the least covered spot.
    struct Layout { var baskets: Int, pair: Bool, island: Int, house: Int }
    static func layout(_ info: SceneInfo, w: Int) -> Layout {
        var taken = occupied(info, w: w)
        let W = CGFloat(w), house = clear(13, [w - 14, 1, Int(W * 0.62)], taken)
        taken.append(house..<(house + 13))   // the baskets keep clear of the house too
        let two = clear(24, [Int(W * 0.25), 1, w - 25], taken), one = clear(12, [Int(W * 0.25), 1, 35], taken)
        let pair = cover(two, 24, taken) <= cover(one, 12, taken)
        return Layout(baskets: pair ? two : one, pair: pair, island: clear(8, [w - 20, w - 9, Int(W * 0.62)], taken), house: house)
    }

    static let cloud = [
        "......yyyy........",
        "....yywwwwy...yy..",
        "...ywwwwwwwyyywwy.",
        "..ywwwwwwwwwwwwwwy",
        ".ywwwwwwwwwwwwwwwy",
        "yywwwwwwwwwwwwwwyy",
        ".yybbyyyyyyyybbyy.",
    ]
    /// Left of the sun, around the peak: Grandpa's speech bubble covers the sky at the right.
    static func cloudSpots(w W: CGFloat) -> [(Int, Int)] { [(1, 0), (Int(floor(W * 0.26)), 13)] }

    /// #9 auspicious clouds (祥雲), drawn in front of the mountain.
    static func sky(_ c: CGContext, _ info: SceneInfo, w W: CGFloat, night: Bool) {
        guard info.titles >= 9 else { return }
        let col: [Character: NSColor] = ["w": night ? hx(0xE6E2F2) : p.birdWhite, "y": RewardColors.gold, "b": hx(0x3E6FC9)]
        for (i, (x, y)) in cloudSpots(w: W).enumerated() { sprite(c, cloud, x: x, y: y, col, mirror: i == 1) }
    }

    static let house = [
        "....T........",
        "...hhhhhh..s.",
        "..hhhhhhhhhs.",
        ".hhhhhhhhhhh.",
        "HHHHHHHHHHHHH",
        ".cccccdcccwc.",
        ".cccccdcccwc.",
        ".ccccccccccc.",
        ".nnnnnnnnnnn.",
    ]

    /// #5 the Bohai Sea on the horizon with the dumped earth piling up in it.
    static func horizon(_ c: CGContext, _ info: SceneInfo, _ lay: Layout, w W: CGFloat, g: CGFloat, night: Bool) {
        if info.titles >= 5 {
            let x0 = Int(floor(W * 0.60)), sea = night ? p.jacketDark : p.birdBlue, crest = night ? p.jacketLight : p.sweat
            c.setFillColor(sea.cgColor); c.fill(CGRect(x: x0, y: Int(g) - 5, width: Int(W) - x0, height: 5))
            c.setFillColor(crest.cgColor)
            for x in stride(from: x0 + 1, to: Int(W), by: 4) { c.fill(CGRect(x: x, y: Int(g) - 5 + (x / 4) % 3 * 2, width: 2, height: 1)) }
            sprite(c, ["...ee...", ".eeEEee.", "eeeeEEEe"], x: lay.island, y: Int(g) - 7, ["e": p.earth, "E": p.earthDark], outline: RewardColors.edge)
        }
    }

    /// #6 terraced fields (다랑이 밭) on the carved slope, ripe with grain. Not while a mountain is being carried.
    static func mountain(_ c: CGContext, _ info: SceneInfo, _ pts: [CGPoint], w W: CGFloat, g: CGFloat, night: Bool) {
        guard info.titles >= 6, info.cutscene == nil else { return }
        let peakX = pts.min(by: { $0.y < $1.y })?.x ?? W * 0.2
        let crop = night ? p.hatDark : RewardColors.gold
        for (i, dy) in [3, 7, 11, 15].enumerated() {
            let y = Int(g) - dy, xStart = 1 + i * 2, xEnd = Int(peakX) - 3 - i
            guard xEnd > xStart else { continue }
            for x in xStart..<xEnd {
                guard let top = YugongArt.ridgeY(pts, CGFloat(x) + 0.5), top < CGFloat(y) - 1 else { continue }
                c.setFillColor((x % 2 == 0 || night ? crop : p.hat).cgColor); c.fill(CGRect(x: x, y: y, width: 1, height: 1))
                c.setFillColor(p.earthDark.cgColor); c.fill(CGRect(x: x, y: y + 1, width: 1, height: 1))
            }
        }
    }

    static let basket = [
        "...eeEEee...",
        ".eeeEEeeeEe.",
        "ohHhHhHhHhHo",
        "oHhHhHhHhHho",
        ".ohHhHhHhHo.",
        "..oooooooo..",
    ]
    static let tipped = [
        "o.........",
        "oHh.......",
        "ohHhH.....",
        "oHhHhHhH..",
        "ohHhHhHhHh",
        ".ooooooooo",
    ]
    static let banner = [
        "tttttttt",
        "wwwwwwww",
        "wwwwkwww",
        "wwwwwwww",
        "wwwwkwww",
        "wwwwwwww",
        "wwwwkwww",
        "wwwwwwww",
        "wwwwkwww",
        "wwwwwwww",
        "ww.www.w",
    ]
    static func bannerX(w W: CGFloat) -> Int { Int(floor(W * 0.22)) }

    /// #3 broken stones at the dig face; #4 two baskets; #7 the family's thatched house; #8 the family banner (농기);
    /// #10 an open road with a milestone. Drawn after the mountain, so a house at its foot stands in front of it.
    static func ground(_ c: CGContext, _ info: SceneInfo, _ lay: Layout, w W: CGFloat, g: CGFloat, night: Bool) {
        if info.titles >= 7 {
            let hy = Int(g) - 9
            sprite(c, house, x: lay.house, y: hy, ["h": p.hat, "H": p.hatDark, "T": p.hatDark, "c": RewardColors.cream, "d": p.woodDark,
                                                    "w": night ? RewardColors.gold : p.woodDark, "n": p.earthDark, "s": p.woodDark],
                   outline: RewardColors.edge)
            c.setFillColor(p.beardShade.cgColor)   // smoke from the chimney
            for (dx, dy) in [(11, -2), (12, -3), (12, -4), (13, -5), (13, -6)] { c.fill(CGRect(x: lay.house + dx, y: hy + dy, width: 1, height: 1)) }
        }
        if info.titles >= 10 {
            c.setFillColor(RewardColors.road.cgColor); c.fill(CGRect(x: 0, y: g + 2, width: W, height: 2))
            c.setFillColor(p.pantsDark.cgColor)
            for x in stride(from: 2, to: Int(W), by: 6) { c.fill(CGRect(x: x, y: Int(g) + 3, width: 2, height: 1)) }
            sprite(c, [".www.", "wwwww", ".www.", "..d..", "..d..", "..d.."], x: 2, y: Int(g) - 5, ["w": p.wood, "d": p.woodDark], outline: RewardColors.edge)
            c.setFillColor(p.birdWhite.cgColor); c.fill(CGRect(x: 3, y: Int(g) - 4, width: 3, height: 1))
        }
        if info.titles >= 8 {   // white, a column of characters, a pheasant-feather top
            let fx = bannerX(w: W)
            c.setFillColor(p.woodDark.cgColor); c.fill(CGRect(x: fx, y: 9, width: 1, height: Int(g) - 9))
            sprite(c, ["..oo.", ".okko", "..oo."], x: fx - 2, y: 6, ["o": p.outline, "k": p.kidHair])
            sprite(c, banner, x: fx - 8, y: 10, ["w": p.birdWhite, "k": p.outline, "t": RewardColors.teal], outline: RewardColors.edge)
        }
        if info.titles >= 4 {
            let col: [Character: NSColor] = ["h": p.hat, "H": p.hatDark, "o": p.band, "e": p.earth, "E": p.earthDark]
            sprite(c, basket, x: lay.baskets, y: Int(g) - 6, col, outline: RewardColors.edge)
            if lay.pair { sprite(c, tipped, x: lay.baskets + 13, y: Int(g) - 6, col, outline: RewardColors.edge) }
        }
        if info.titles >= 3 {
            sprite(c, ["...ss......", ".sSsss.sS..", "sSSsSsssSss"], x: Int(floor(W * 0.43)), y: Int(g) - 3,
                   ["s": p.iron, "S": p.ironDark], outline: RewardColors.edge)
        }
    }

    // MARK: the unlock sparkle

    /// Where reward `n` sits (cells, y down), for the sparkle while its title is celebrated.
    static func spot(_ n: Int, _ info: SceneInfo, w: Int, h: Int) -> CGRect {
        let W = CGFloat(w), g = CGFloat(h - 6), fx = CGFloat(Int(W * 0.42)), lay = layout(info, w: w)
        switch n {
        case 1: return CGRect(x: fx + 4, y: g - 14, width: 18, height: 14)       // the shovel
        case 2: return CGRect(x: fx + 22, y: g - 28, width: 10, height: 10)                         // the tassel
        case 3: return CGRect(x: fx + 18, y: g - 34, width: 16, height: 10)                         // the pickaxe
        case 4: return CGRect(x: CGFloat(lay.baskets), y: g - 7, width: 24, height: 7)
        case 5: return CGRect(x: floor(W * 0.6), y: g - 7, width: W - floor(W * 0.6), height: 7)
        case 6: return CGRect(x: 2, y: g - 16, width: max(4, W * 0.25), height: 14)
        case 7: return CGRect(x: CGFloat(lay.house), y: g - 10, width: 13, height: 10)
        case 8: return CGRect(x: CGFloat(bannerX(w: W) - 8), y: 6, width: 10, height: 16)
        case 9: return CGRect(x: 1, y: 0, width: floor(W * 0.26) + 17, height: 20)
        default: return CGRect(x: 0, y: g - 6, width: W * 0.6, height: 10)                           // road, milestone, golden blade
        }
    }

    /// Four little stars twinkling over reward `n` (`t` in seconds), on a transparent w x h layer.
    static func sparkle(_ c: CGContext, _ n: Int, _ info: SceneInfo, t: Double, w: Int, h: Int) {
        let r = spot(n, info, w: w, h: h)
        for i in 0..<4 {
            let on = Int(t * 4 + Double(i) * 1.7) % 3   // 0 off, 1 small, 2 big
            guard on > 0 else { continue }
            let u = (CGFloat(i) * 0.618).truncatingRemainder(dividingBy: 1), v = (CGFloat(i) * 0.38 + 0.2).truncatingRemainder(dividingBy: 1)
            let x = Int(r.minX + u * r.width), y = Int(r.minY + v * r.height)
            c.setFillColor((i % 2 == 0 ? p.birdWhite : RewardColors.gold).cgColor)
            c.fill(CGRect(x: x, y: y, width: 1, height: 1))
            if on == 2 { for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] { c.fill(CGRect(x: x + dx, y: y + dy, width: 1, height: 1)) } }
        }
    }
}

// MARK: - the review sheet (YugongSheet --rewards)

extension YugongSheet {
    static let rewardNames = ["iron shovel", "tassel", "pickaxe + stones", "baskets", "Bohai Sea", "terraces",
                              "house", "banner", "clouds", "road, milestone, golden shovel"]
    public static let rewardsSize = NSSize(width: 18 + 5 * 318, height: 1500)

    static func rewardScene(_ titles: Int, mountain: Double = 0.8, night: Bool = false, family: Bool = false, grandson: Bool = true,
                            props: Bool = true, finale: Double? = nil, sparkle: Int? = nil) -> NSImage {
        var i = SceneInfo(state: .lively, carrier: 0.5, mountainLeft: mountain, grandson: grandson || family ? 0.3 : nil, night: night,
                          cutscene: finale)
        if family { i.son = 0.4; i.boy = 0.2 }
        i.titles = titles; i.props = props; i.finale = finale != nil; i.sparkle = sparkle
        return YugongArt.scene(i, t: 0.9, size: CGSize(width: 292, height: 176))
    }

    /// Every title before and after (with the grandson, the default family), the menu bar at 4x, then the
    /// busy cases (the whole family by day and night, props hidden) and the finale frame by frame.
    public static func drawRewardsSheet() {
        NSColor(srgbRed: 0.97, green: 0.95, blue: 0.91, alpha: 1).setFill(); NSRect(origin: .zero, size: rewardsSize).fill()
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ sz: CGFloat, _ w: NSFont.Weight = .regular) {
            (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: sz, weight: w),
                                                                         .foregroundColor: NSColor(white: 0.15, alpha: 1)])
        }
        func draw(_ img: NSImage, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 292, _ h: CGFloat = 176) {
            img.draw(in: NSRect(x: x, y: y, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        for n in 1...10 {
            let x = 18 + CGFloat((n - 1) % 5) * 318, y = 12 + CGFloat((n - 1) / 5) * 430
            text("#\(n)  \(rewardNames[n - 1])", x, y, 15, .bold)
            draw(rewardScene(n - 1), x, y + 24)
            draw(rewardScene(n, sparkle: n), x, y + 206)
            for (j, lv) in [n - 1, n].enumerated() {
                NSColor(white: 0.9, alpha: 1).setFill(); NSRect(x: x + CGFloat(j) * 100, y: y + 388, width: 40, height: 40).fill()
                draw(YugongArt.figure(.lively, t: 0.9, carrier: 0.5, night: false, size: 20, menuBar: true, titles: lv), x + CGFloat(j) * 100, y + 388, 40, 40)
                NSColor(white: 0.16, alpha: 1).setFill(); NSRect(x: x + CGFloat(j) * 100 + 44, y: y + 388, width: 40, height: 40).fill()
                draw(YugongArt.figure(.lively, t: 0.9, carrier: 0.5, night: true, size: 20, menuBar: true, titles: lv), x + CGFloat(j) * 100 + 44, y + 388, 40, 40)
            }
        }
        let y = 880.0
        text("all ten, the whole family, day / night / props hidden / no titles (wooden shovel)", 18, y, 15, .bold)
        draw(rewardScene(10, mountain: 0.6, family: true), 18, y + 24)
        draw(rewardScene(10, mountain: 0.6, night: true, family: true), 336, y + 24)
        draw(rewardScene(10, mountain: 0.6, family: true, props: false), 654, y + 24)
        draw(rewardScene(0, mountain: 0.6, family: true), 972, y + 24)
        draw(rewardScene(10, mountain: 0.6, grandson: false), 1290, y + 24)
        text("the #10 finale: Kua'e's sons carry both mountains off", 18, y + 214, 15, .bold)
        for (i, c) in [0.05, 0.3, 0.5, 0.75, 0.95].enumerated() {
            draw(rewardScene(10, mountain: 0.6, finale: c), 18 + CGFloat(i) * 318, y + 238)
        }
    }
}
