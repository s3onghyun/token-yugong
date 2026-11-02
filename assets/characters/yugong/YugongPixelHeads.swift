import AppKit

// Hand-placed pixel heads. The head carries the charm (hat, eyes, beard),
// so it is drawn pixel by pixel instead of being rasterized from the vector rig.
// One character per pixel; "." is transparent. Faces LEFT; mirrored when he looks back.

enum PixelHeads {
    static let colors: [Character: NSColor] = {
        let p = Palette.pixel
        return ["o": p.outline, "k": p.outline, "h": p.hat, "H": p.hatDark, "n": p.band, "s": p.skin,
                "S": NSColor(srgbRed: 0.88, green: 0.66, blue: 0.53, alpha: 1), "r": p.nose, "p": p.blush,
                "w": p.beard, "W": p.beardShade, "m": p.mouth]
    }()

    /// Popover / sheet size (figure grid about 40 px). Anchor = skull centre.
    static let big: [String] = [
        "......oooooo......",
        ".....ohhhhhhoo....",
        "....ohhhhhhhhho...",
        "....onnnnnnnnno...",
        "..oohhhhhhhhhhhoo.",
        "oohhhhhhhhhhhhhhho",
        ".oHHHHHHHHHHHHHHo.",
        "..owwwssswwsswwwo.",
        "..ossksssskssswwo.",
        ".orrrksppsksSswwo.",
        ".owwwwwwsssssswwo.",
        ".owwwwwwwwwwssso..",
        ".owwwwwwwwwwWoo...",
        "..owwwwwwwwWo.....",
        "..owwwwwwWo.......",
        "...owwwWo.........",
        "....owo...........",
    ]
    static let bigAnchor = (x: 9, y: 9)

    /// Menu-bar size (figure grid about 20 px).
    static let small: [String] = [
        "...ooooo...",
        "..ohhhhho..",
        "oohhhhhhhoo",
        ".oHHHHHHHo.",
        ".oskssswwo.",
        "orrssspswo.",
        "owwwwwwsso.",
        ".owwwwwwo..",
        "..owwwwo...",
        "...owwo....",
        "....oo.....",
    ]
    static let smallAnchor = (x: 5, y: 5)

    /// Patches per expression: (row, col, pixel).
    static func patches(_ p: YPose, small: Bool) -> [(Int, Int, Character)] {
        var out: [(Int, Int, Character)] = []
        if small {
            switch p.eyes {
            case .open: break
            case .closed, .happy, .squeeze: out += [(4, 3, "s"), (4, 2, "k"), (4, 3, "k")]
            }
            switch p.mouth {
            case .open, .snore: out += [(6, 3, "m")]
            case .yawn: out += [(6, 3, "m"), (6, 4, "m"), (7, 3, "m")]
            case .smile: break
            }
            return out
        }
        switch p.eyes {
        case .open: break
        case .closed: out += [(8, 5, "s"), (8, 10, "s"), (9, 6, "k"), (9, 11, "k")]
        case .happy:   // little upside-down Vs
            out += [(9, 5, "s"), (9, 10, "s"), (8, 5, "s"), (8, 10, "s"), (7, 5, "k"), (8, 4, "k"), (8, 6, "k"),
                    (7, 10, "k"), (8, 9, "k"), (8, 11, "k")]
        case .squeeze: out += [(9, 5, "s"), (8, 10, "s"), (9, 6, "k"), (9, 10, "k")]
        }
        switch p.mouth {
        case .open: out += [(11, 4, "m"), (11, 5, "m")]
        case .yawn: out += [(11, 3, "m"), (11, 4, "m"), (11, 5, "m"), (12, 3, "m"), (12, 4, "m"), (12, 5, "m"), (13, 4, "m")]
        case .snore: out += [(11, 4, "m")]
        case .smile: break
        }
        return out
    }

    /// Stamps the head with its expression at canvas point `c` (units 0...100) on an n-pixel grid.
    static func stamp(_ ctx: CGContext, pose p: YPose, at spot: YugongArt.HeadSpot, grid n: Int, small: Bool? = nil) {
        let small = small ?? (n < 30)
        var rows = (small ? Self.small : big).map { Array($0) }
        if p.hatTip > 0.5 && !small {
            // napping: the hat slides down over his eyes
            let hat = Array(rows[0...6])
            rows = [Array(repeating: ".", count: 18), Array(repeating: ".", count: 18)] + hat + Array(rows[9...])
        } else {
            for (r, c, ch) in patches(p, small: small) where r < rows.count && c < rows[r].count { rows[r][c] = ch }
            if p.hatTip > 0.5 && small { rows[4] = Array(".oHHHHHHHo.") }
        }
        let anchor = small ? smallAnchor : bigAnchor
        let w = rows[0].count
        let ox = Int((spot.center.x * CGFloat(n) / 100).rounded()) - (spot.mirror ? (w - 1 - anchor.x) : anchor.x)
        let oy = Int((spot.center.y * CGFloat(n) / 100).rounded()) - anchor.y
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch != "." {
                guard let col = colors[ch] else { continue }
                ctx.setFillColor(col.cgColor)
                let dx = spot.mirror ? (w - 1 - x) : x
                ctx.fill(CGRect(x: ox + dx, y: oy + y, width: 1, height: 1))
            }
        }
    }

    /// A small outlined block (a hand, a clump of earth) stamped over the head.
    static func blob(_ ctx: CGContext, at p: CGPoint, grid n: Int, fill: NSColor, w: Int, h: Int) {
        let x = Int((p.x * CGFloat(n) / 100).rounded()) - w / 2, y = Int((p.y * CGFloat(n) / 100).rounded()) - h / 2
        ctx.setFillColor(Palette.pixel.outline.cgColor)
        ctx.fill(CGRect(x: x - 1, y: y, width: w + 2, height: h)); ctx.fill(CGRect(x: x, y: y - 1, width: w, height: h + 2))
        ctx.setFillColor(fill.cgColor); ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    /// Sleepy z's drifting up from the napping head, on whole pixels.
    static func zzz(_ ctx: CGContext, above head: CGPoint, k: CGFloat, grid n: Int) {
        let glyphs: [[String]] = n < 30 ? [["###", ".#.", "###"]] : [["###", ".#.", "###"], ["####", "..#.", ".#..", "####"]]
        let hx = Int((head.x * CGFloat(n) / 100).rounded()), hy = Int((head.y * CGFloat(n) / 100).rounded())
        let rise = Int(floor(k * 3))
        for (i, g) in glyphs.enumerated() {
            let ox = hx - (n < 30 ? 6 : 8) - i * 5, oy = hy - (n < 30 ? 9 : 13) - i * 5 - rise
            for (r, row) in g.enumerated() {
                for (c, ch) in row.enumerated() where ch == "#" {
                    ctx.setFillColor((n < 30 ? Palette.pixel.birdBlue : NSColor.white).cgColor); ctx.fill(CGRect(x: ox + c, y: oy + r, width: 1, height: 1))
                }
            }
        }
    }

    // MARK: - turnaround heads and the magpie

    static let front: [String] = [
        ".......ooooo.......",
        ".....oohhhhhoo.....",
        "....ohhhhhhhhho....",
        "....onnnnnnnnno....",
        "..oohhhhhhhhhhhoo..",
        "oohhhhhhhhhhhhhhhoo",
        ".oHHHHHHHHHHHHHHHo.",
        "..oswwwssssswwwso..",
        "..ossskssssskssso..",
        "..ospsksrrrskspso..",
        ".owwwwwwwrwwwwwwwo.",
        ".owwwwwwwwwwwwwwwo.",
        "..owwwwwwwwwwwwwo..",
        "...owwwwwwwwwwwo...",
        "....owwwwwwwwwo....",
        ".....owwwwwwwo.....",
        "......owwwwwo......",
        ".......owwwo.......",
        "........owo........",
    ]
    static let back: [String] = [
        ".......ooooo.......",
        ".....oohhhhhoo.....",
        "....ohhhhhhhhho....",
        "....onnnnnnnnno....",
        "..oohhhhhhhhhhhoo..",
        "oohhhhhhhhhhhhhhhoo",
        ".oHHHHHHHHHHHHHHHo.",
        "..owwwwwwwwwwwwwo..",
        "..owwwwwwwwwwwwwo..",
        ".osowwwwwwwwwwwoso.",
        "..owwwwwwwWwwwwwo..",
        "...oowwwwWwwwwoo...",
        ".....ooooooooo.....",
    ]

    static func stampRows(_ ctx: CGContext, _ rows: [[Character]], ox: Int, oy: Int, mirror: Bool = false) {
        let w = rows.first?.count ?? 0
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch != "." {
                guard let col = colors[ch] ?? birdColors[ch] else { continue }
                ctx.setFillColor(col.cgColor)
                ctx.fill(CGRect(x: ox + (mirror ? w - 1 - x : x), y: oy + y, width: 1, height: 1))
            }
        }
    }

    static func stampTurn(_ ctx: CGContext, front isFront: Bool, center c: CGPoint, grid n: Int, pose p: YPose = YPose()) {
        var rows = (isFront ? front : back).map { Array($0) }
        if isFront {
            switch p.mouth {
            case .open: rows[11][8] = "m"; rows[11][9] = "m"; rows[11][10] = "m"
            case .yawn: for (r, cs) in [(11, [8, 9, 10]), (12, [8, 9, 10]), (13, [9])] { for x in cs { rows[r][x] = "m" } }
            default: break
            }
            switch p.eyes {
            case .open: break
            case .closed: for x in [6, 12] { rows[8][x] = "s"; rows[9][x] = "k"; rows[9][x + (x == 6 ? -1 : 1)] = "k" }
            case .happy: for x in [6, 12] { rows[9][x] = "s"; rows[8][x] = "s"; rows[7][x] = "k"; rows[8][x - 1] = "k"; rows[8][x + 1] = "k" }
            case .squeeze: rows[8][6] = "k"; rows[9][7] = "k"; rows[9][6] = "s"; rows[8][12] = "k"; rows[9][11] = "k"; rows[9][12] = "s"
            }
        }
        stampRows(ctx, rows, ox: Int((c.x * CGFloat(n) / 100).rounded()) - 9, oy: Int((c.y * CGFloat(n) / 100).rounded()) - 9)
    }

    static let birdColors: [Character: NSColor] = {
        let p = Palette.pixel
        return ["b": p.bird, "B": p.birdBlue, "e": .white, "y": p.bird]
    }()
    static let bird: [String] = [
        "..ooo.......",
        ".obbbo......",
        "oobebbo.....",
        "..obbbbooo..",
        "..owwBbbbbbo",
        "...owwbboooo",
        "....o..o....",
    ]

    static func magpie(_ ctx: CGContext, at foot: CGPoint, _ s: Bird, k: CGFloat, grid n: Int, faceRight: Bool = false) {
        guard n >= 30 else { return }
        var rows = bird.map { Array($0) }
        if s == .sleep { rows[2][3] = "b"; rows[1][1] = "o"; rows[2][0] = "."; rows[2][1] = "o" }
        if s == .chirp && Int(k * 6) % 2 == 0 { rows[1][0] = "o"; rows[2][0] = "." }
        let hop = s == .hop && k > 0.2 && k < 0.7 ? 2 : 0
        stampRows(ctx, rows, ox: Int((foot.x * CGFloat(n) / 100).rounded()) - 5,
                  oy: Int((foot.y * CGFloat(n) / 100).rounded()) - 6 - hop, mirror: faceRight)
    }
}
