import AppKit

public enum PetState: String, CaseIterable {
    case lively, full, asleep, stretch
}

/// Toki (style A, soft vector), drawn entirely with vector shapes on a 100x100, y-down canvas.
/// Every state has three animation frames.
public enum TokiArt {
    static let ink = NSColor(srgbRed: 0.24, green: 0.16, blue: 0.17, alpha: 1)

    public static func image(_ state: PetState, frame: Int, size: CGFloat, menuBar: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.scaleBy(x: rect.width / 100, y: rect.height / 100)
            draw(state, frame: ((frame % 3) + 3) % 3, menuBar: menuBar)
            return true
        }
        img.isTemplate = false
        return img
    }

    // MARK: - drawing

    private static func draw(_ s: PetState, frame f: Int, menuBar mb: Bool) {
        let lw: CGFloat = mb ? 6.0 : 3.0
        let ground: CGFloat = mb ? 97 : 90

        var rx: CGFloat = 31, ry: CGFloat = 25, lift: CGFloat = 0
        var earAngle: CGFloat = 12, earLen: CGFloat = 22
        var body = NSColor(srgbRed: 1.00, green: 0.80, blue: 0.62, alpha: 1)
        switch s {
        case .lively:
            lift = [0, 7, 2][f]
            if f == 1 { ry += 1.5; rx -= 1 }
            earAngle = [12, 6, 16][f]
        case .full:
            rx = 37; ry = 27 + [0, 1.5, 0.5][f]
            earAngle = 30; earLen = 20
            body = NSColor(srgbRed: 1.00, green: 0.72, blue: 0.56, alpha: 1)
        case .asleep:
            rx = 35; ry = 21 + [0, 1, 2][f]
            earAngle = 72; earLen = 18
            body = NSColor(srgbRed: 0.93, green: 0.80, blue: 0.74, alpha: 1)
        case .stretch:
            rx = [38, 26, 30][f]; ry = [20, 34, 29][f]
            earAngle = [20, 2, 8][f]; earLen = [18, 26, 23][f]
        }
        if mb { rx += 4; ry += 3 }
        let cx: CGFloat = 50
        let cy = ground - ry - lift

        // ground shadow
        if !mb {
            NSColor.black.withAlphaComponent(0.13).setFill()
            let sw = rx * (lift > 3 ? 0.65 : 0.85)
            NSBezierPath(ovalIn: NSRect(x: cx - sw, y: ground - 3, width: sw * 2, height: 6)).fill()
        }

        // stretch arms go behind the body
        if s == .stretch && f >= 1 {
            for side: CGFloat in [-1, 1] {
                let base = NSPoint(x: cx + side * rx * 0.75, y: cy - ry * 0.25)
                drawRotatedOval(center: NSPoint(x: base.x + side * 4, y: base.y - 12), w: 9, h: 22,
                                angle: side * 28, fill: body, lw: lw)
            }
        }

        // ears
        for side: CGFloat in [-1, 1] {
            let base = NSPoint(x: cx + side * rx * 0.42, y: cy - ry * 0.78)
            let ear = NSAffineTransform()
            ear.translateX(by: base.x, yBy: base.y)
            ear.rotate(byDegrees: side * earAngle)
            let p = NSBezierPath(ovalIn: NSRect(x: -6, y: -earLen, width: 12, height: earLen + 6))
            p.transform(using: ear as AffineTransform)
            body.setFill(); p.fill()
            ink.setStroke(); p.lineWidth = lw; p.stroke()
            if !mb {
                let inner = NSBezierPath(ovalIn: NSRect(x: -2.6, y: -earLen + 5, width: 5.2, height: earLen - 4))
                inner.transform(using: ear as AffineTransform)
                NSColor(srgbRed: 1, green: 0.62, blue: 0.66, alpha: 0.9).setFill(); inner.fill()
            }
        }

        // body
        let bodyPath = NSBezierPath(ovalIn: NSRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        body.setFill(); bodyPath.fill()
        if !mb {
            NSColor(srgbRed: 1, green: 0.95, blue: 0.86, alpha: 1).setFill()
            let bw = rx * (s == .full ? 0.66 : 0.52), bh = ry * (s == .full ? 0.55 : 0.45)
            NSBezierPath(ovalIn: NSRect(x: cx - bw, y: cy + ry * 0.92 - bh * 2 + 2, width: bw * 2, height: bh * 2)).fill()
        }
        ink.setStroke(); bodyPath.lineWidth = lw; bodyPath.stroke()

        // face
        let ey = cy - ry * 0.10
        let edx = max(rx * 0.36, mb ? 13 : 10)
        let eyeL = NSPoint(x: cx - edx, y: ey), eyeR = NSPoint(x: cx + edx, y: ey)
        let mouthY = ey + (mb ? 10 : 8)

        // cheeks
        if !mb || s == .full {
            let cheek = s == .full ? NSColor(srgbRed: 1, green: 0.42, blue: 0.45, alpha: 0.75)
                                   : NSColor(srgbRed: 1, green: 0.55, blue: 0.58, alpha: 0.55)
            cheek.setFill()
            for side: CGFloat in [-1, 1] {
                let chx = cx + side * (edx + (mb ? 7 : 8))
                NSBezierPath(ovalIn: NSRect(x: chx - 4.5, y: ey + 3, width: 9, height: 5)).fill()
            }
        }

        let eyeW: CGFloat = mb ? 9 : 6.5, eyeH: CGFloat = mb ? 11 : 8
        switch s {
        case .lively:
            if f == 2 { closedEyes(eyeL, eyeR, up: true, lw: lw, mb: mb) }
            else { openEyes(eyeL, eyeR, w: eyeW, h: eyeH, mb: mb) }
            if f == 1 {
                ovalMouth(cx, mouthY, w: mb ? 8 : 6, h: mb ? 8 : 6, tongue: false)
            } else {
                catMouth(cx, mouthY, lw: lw, mb: mb)
            }
            if f == 1 && !mb { sparkle(at: NSPoint(x: 84, y: 26), r: 6) ; sparkle(at: NSPoint(x: 16, y: 40), r: 3.5) }
        case .full:
            squintEyes(eyeL, eyeR, lw: lw, mb: mb)
            let open: [CGFloat] = [7, 10, 6]
            ovalMouth(cx, mouthY, w: mb ? 11 : 9, h: open[f] * (mb ? 1.15 : 1), tongue: true)
            sweat(at: NSPoint(x: cx + rx * 0.9, y: cy - ry * 0.55 + CGFloat(f) * 3), mb: mb)
            if !mb {
                NSColor(srgbRed: 0.75, green: 0.85, blue: 1, alpha: 0.9).setStroke()
                for i in 0..<2 where (f + i) % 2 == 0 {
                    let p = NSBezierPath()
                    let x = cx - rx - 6 - CGFloat(i) * 6, y = mouthY - 2 + CGFloat(i) * 6
                    p.move(to: NSPoint(x: x + 5, y: y)); p.line(to: NSPoint(x: x - 3, y: y))
                    p.lineWidth = 2.4; p.lineCapStyle = .round; p.stroke()
                }
            }
        case .asleep:
            closedEyes(eyeL, eyeR, up: false, lw: lw, mb: mb)
            ovalMouth(cx, mouthY, w: mb ? 5 : 4, h: mb ? 5 : 3.5, tongue: false)
            if !mb {
                let r: [CGFloat] = [2.5, 4.5, 6.5]
                let bubble = NSBezierPath(ovalIn: NSRect(x: cx + 4, y: mouthY - r[f] + 2, width: r[f] * 2, height: r[f] * 2))
                NSColor(srgbRed: 0.72, green: 0.86, blue: 1, alpha: 0.55).setFill(); bubble.fill()
                NSColor(srgbRed: 0.45, green: 0.62, blue: 0.9, alpha: 0.9).setStroke(); bubble.lineWidth = 1.4; bubble.stroke()
            }
            zzz(frame: f, mb: mb)
        case .stretch:
            switch f {
            case 0: closedEyes(eyeL, eyeR, up: false, lw: lw, mb: mb); catMouth(cx, mouthY, lw: lw, mb: mb)
            case 1: closedEyes(eyeL, eyeR, up: true, lw: lw, mb: mb)
                    ovalMouth(cx, mouthY + 1, w: mb ? 10 : 9, h: mb ? 11 : 11, tongue: false)
            default: openEyes(eyeL, eyeR, w: eyeW, h: eyeH, mb: mb); smile(cx, mouthY, lw: lw, mb: mb)
            }
            if f == 2 && !mb {
                sparkle(at: NSPoint(x: 16, y: 26), r: 5); sparkle(at: NSPoint(x: 86, y: 34), r: 6)
                sparkle(at: NSPoint(x: 78, y: 12), r: 3)
            }
        }
    }

    private static func drawRotatedOval(center: NSPoint, w: CGFloat, h: CGFloat, angle: CGFloat, fill: NSColor, lw: CGFloat) {
        let t = NSAffineTransform()
        t.translateX(by: center.x, yBy: center.y); t.rotate(byDegrees: angle)
        let p = NSBezierPath(ovalIn: NSRect(x: -w / 2, y: -h / 2, width: w, height: h))
        p.transform(using: t as AffineTransform)
        fill.setFill(); p.fill(); ink.setStroke(); p.lineWidth = lw; p.stroke()
    }

    private static func openEyes(_ l: NSPoint, _ r: NSPoint, w: CGFloat, h: CGFloat, mb: Bool) {
        for e in [l, r] {
            ink.setFill()
            NSBezierPath(ovalIn: NSRect(x: e.x - w / 2, y: e.y - h / 2, width: w, height: h)).fill()
            if !mb {
                NSColor.white.setFill()
                NSBezierPath(ovalIn: NSRect(x: e.x - w / 2 + 1.2, y: e.y - h / 2 + 1.2, width: w * 0.42, height: w * 0.42)).fill()
            }
        }
    }

    /// up=true draws happy "^" arcs; up=false draws sleepy "u" arcs.
    private static func closedEyes(_ l: NSPoint, _ r: NSPoint, up: Bool, lw: CGFloat, mb: Bool) {
        let hw: CGFloat = mb ? 6 : 4.5
        for e in [l, r] {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: e.x - hw, y: e.y))
            let cy = up ? e.y - hw * 1.1 : e.y + hw * 0.9
            p.curve(to: NSPoint(x: e.x + hw, y: e.y), controlPoint1: NSPoint(x: e.x - hw / 2, y: cy), controlPoint2: NSPoint(x: e.x + hw / 2, y: cy))
            ink.setStroke(); p.lineWidth = lw * 0.9; p.lineCapStyle = .round; p.stroke()
        }
    }

    private static func squintEyes(_ l: NSPoint, _ r: NSPoint, lw: CGFloat, mb: Bool) {
        let s: CGFloat = mb ? 5.5 : 4
        for (e, dir) in [(l, CGFloat(1)), (r, CGFloat(-1))] {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: e.x - dir * s, y: e.y - s))
            p.line(to: NSPoint(x: e.x + dir * s * 0.8, y: e.y))
            p.line(to: NSPoint(x: e.x - dir * s, y: e.y + s))
            ink.setStroke(); p.lineWidth = lw * 0.9; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
        }
    }

    private static func catMouth(_ x: CGFloat, _ y: CGFloat, lw: CGFloat, mb: Bool) {
        let w: CGFloat = mb ? 5 : 3.6
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x - w * 2, y: y - 1))
        p.curve(to: NSPoint(x: x, y: y - 1), controlPoint1: NSPoint(x: x - w * 1.6, y: y + w), controlPoint2: NSPoint(x: x - w * 0.4, y: y + w))
        p.curve(to: NSPoint(x: x + w * 2, y: y - 1), controlPoint1: NSPoint(x: x + w * 0.4, y: y + w), controlPoint2: NSPoint(x: x + w * 1.6, y: y + w))
        ink.setStroke(); p.lineWidth = lw * 0.8; p.lineCapStyle = .round; p.stroke()
    }

    private static func smile(_ x: CGFloat, _ y: CGFloat, lw: CGFloat, mb: Bool) {
        let w: CGFloat = mb ? 8 : 6
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x - w, y: y - 2))
        p.curve(to: NSPoint(x: x + w, y: y - 2), controlPoint1: NSPoint(x: x - w / 2, y: y + w), controlPoint2: NSPoint(x: x + w / 2, y: y + w))
        ink.setStroke(); p.lineWidth = lw * 0.8; p.lineCapStyle = .round; p.stroke()
    }

    private static func ovalMouth(_ x: CGFloat, _ y: CGFloat, w: CGFloat, h: CGFloat, tongue: Bool) {
        let r = NSRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
        NSColor(srgbRed: 0.55, green: 0.18, blue: 0.22, alpha: 1).setFill()
        NSBezierPath(ovalIn: r).fill()
        if tongue {
            NSColor(srgbRed: 1, green: 0.48, blue: 0.55, alpha: 1).setFill()
            let tw = w * 0.62
            NSBezierPath(roundedRect: NSRect(x: x - tw / 2, y: y, width: tw, height: h * 0.5 + 3), xRadius: tw / 2, yRadius: tw / 2).fill()
        }
    }

    private static func sweat(at p: NSPoint, mb: Bool) {
        let s: CGFloat = mb ? 1.6 : 1
        let d = NSBezierPath()
        d.move(to: NSPoint(x: p.x, y: p.y - 6 * s))
        d.curve(to: NSPoint(x: p.x, y: p.y + 4 * s), controlPoint1: NSPoint(x: p.x + 6 * s, y: p.y + 1 * s), controlPoint2: NSPoint(x: p.x + 5 * s, y: p.y + 4 * s))
        d.curve(to: NSPoint(x: p.x, y: p.y - 6 * s), controlPoint1: NSPoint(x: p.x - 5 * s, y: p.y + 4 * s), controlPoint2: NSPoint(x: p.x - 6 * s, y: p.y + 1 * s))
        NSColor(srgbRed: 0.55, green: 0.80, blue: 1, alpha: 1).setFill(); d.fill()
        if !mb { NSColor(srgbRed: 0.3, green: 0.55, blue: 0.85, alpha: 1).setStroke(); d.lineWidth = 1.2; d.stroke() }
    }

    private static func sparkle(at c: NSPoint, r: CGFloat) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x, y: c.y - r))
        p.curve(to: NSPoint(x: c.x + r, y: c.y), controlPoint1: NSPoint(x: c.x + r * 0.15, y: c.y - r * 0.15), controlPoint2: NSPoint(x: c.x + r * 0.15, y: c.y - r * 0.15))
        p.curve(to: NSPoint(x: c.x, y: c.y + r), controlPoint1: NSPoint(x: c.x + r * 0.15, y: c.y + r * 0.15), controlPoint2: NSPoint(x: c.x + r * 0.15, y: c.y + r * 0.15))
        p.curve(to: NSPoint(x: c.x - r, y: c.y), controlPoint1: NSPoint(x: c.x - r * 0.15, y: c.y + r * 0.15), controlPoint2: NSPoint(x: c.x - r * 0.15, y: c.y + r * 0.15))
        p.curve(to: NSPoint(x: c.x, y: c.y - r), controlPoint1: NSPoint(x: c.x - r * 0.15, y: c.y - r * 0.15), controlPoint2: NSPoint(x: c.x - r * 0.15, y: c.y - r * 0.15))
        NSColor(srgbRed: 1, green: 0.78, blue: 0.2, alpha: 1).setFill(); p.fill()
    }

    private static func zzz(frame f: Int, mb: Bool) {
        let color = NSColor(srgbRed: 0.42, green: 0.45, blue: 0.85, alpha: 1)
        if mb {
            // one bobbing Z keeps the 22pt icon readable
            drawText("z", at: NSPoint(x: 74, y: 2 + CGFloat(f) * 3), size: 34, color: color)
            return
        }
        let spots: [(NSPoint, CGFloat)] = [(NSPoint(x: 70, y: 30), 13), (NSPoint(x: 79, y: 15), 17), (NSPoint(x: 88, y: -1), 21)]
        for i in 0...f { drawText(i == 0 ? "z" : "Z", at: spots[i].0, size: spots[i].1, color: color) }
    }

    private static func drawText(_ s: String, at p: NSPoint, size: CGFloat, color: NSColor) {
        let font = NSFont.systemFont(ofSize: size, weight: .heavy)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
        (s as NSString).draw(at: p, withAttributes: [.font: rounded, .foregroundColor: color])
    }
}
