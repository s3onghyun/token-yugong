import AppKit
import TokenPetAssets

// Renders Grandpa Yugong's character sheet as PNG and PDF (the PDF embeds the sprites as bitmaps).
// usage: YugongSheet <out-dir> [--crop x,y,w,h]   (crop writes extra zoomed review images)
//        YugongSheet <out-dir> --hero     docs/hero.gif frames (hero-NNN.png, 10 fps; README › For development has the ffmpeg line)
//        YugongSheet <out-dir> --social   docs/social-preview.png, 1280x640
let argv = CommandLine.arguments
let out = URL(fileURLWithPath: argv.count > 1 ? argv[1] : ".")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let size = YugongSheet.pageSize

func renderPNG() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    // y-down page
    g.cgContext.translateBy(x: 0, y: size.height); g.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: g.cgContext, flipped: true)
    NSGraphicsContext.current?.imageInterpolation = .none
    YugongSheet.drawSheet()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func renderPDF(_ url: URL) {
    var box = CGRect(origin: .zero, size: size)
    guard let c = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
    c.beginPDFPage(nil)
    c.translateBy(x: 0, y: size.height); c.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
    YugongSheet.drawSheet()
    NSGraphicsContext.restoreGraphicsState()
    c.endPDFPage(); c.closePDF()
}

let sheet = renderPNG()
try! sheet.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("yugong-sheet-pixel.png"))
renderPDF(out.appendingPathComponent("yugong-sheet-pixel.pdf"))
if let i = argv.firstIndex(of: "--crop"), i + 1 < argv.count {
    let v = argv[i + 1].split(separator: ",").compactMap { Int($0) }
    if v.count == 4, let cg = sheet.cgImage?.cropping(to: CGRect(x: v[0], y: v[1], width: v[2], height: v[3])) {
        try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
            .write(to: out.appendingPathComponent("crop-pixel.png"))
    }
}
if let i = argv.firstIndex(of: "--frames"), i + 1 < argv.count, let st = PetState(flag: argv[i + 1]) {
    let img = YugongSheet.frames(st, fps: 6, night: argv.contains("--night"))
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("frames-\(st.rawValue).png"))
}
if argv.contains("--scenes") {
    let img = YugongSheet.sceneStrip()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(img.size.width * 2), pixelsHigh: Int(img.size.height * 2), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = img.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .none
    img.draw(in: NSRect(origin: .zero, size: img.size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("scenes-pixel.png"))
}
if argv.contains("--family") {   // the son and the neighbour's boy, 1x page
    let fs = YugongSheet.familySize
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(fs.width), pixelsHigh: Int(fs.height), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = fs
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    g.cgContext.translateBy(x: 0, y: fs.height); g.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: g.cgContext, flipped: true)
    NSGraphicsContext.current?.imageInterpolation = .none
    YugongSheet.drawFamilySheet()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("family-sheet.png"))
}
if argv.contains("--visitors") {   // the wife, Zhisou and Kua'e's sons, 1x page
    let fs = YugongSheet.visitorsSize
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(fs.width), pixelsHigh: Int(fs.height), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = fs
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    g.cgContext.translateBy(x: 0, y: fs.height); g.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: g.cgContext, flipped: true)
    NSGraphicsContext.current?.imageInterpolation = .none
    YugongSheet.drawVisitorSheet()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("visitors-sheet.png"))
}
if argv.contains("--rewards") {   // the title rewards, before and after, 1x page
    let fs = YugongSheet.rewardsSize
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(fs.width) * 2, pixelsHigh: Int(fs.height) * 2, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = fs
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    g.cgContext.translateBy(x: 0, y: fs.height); g.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: g.cgContext, flipped: true)
    NSGraphicsContext.current?.imageInterpolation = .none
    YugongSheet.drawRewardsSheet()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("rewards-sheet.png"))
}

/// Draws `size` points into a bitmap `scale` times larger, y-down, without smoothing (pixel art stays crisp).
func bitmap(_ size: CGSize, scale: CGFloat, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    g.cgContext.translateBy(x: 0, y: size.height); g.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: g.cgContext, flipped: true)
    NSGraphicsContext.current?.imageInterpolation = .none
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// A Mac menu-bar strip with Grandpa and the number, right-aligned, as the app draws its bar item.
func menuBar(_ r: NSRect, state: PetState, t: Double, carrier: Double, night: Bool, titles: Int, text: String) {
    NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1).setFill(); r.fill()
    let font = NSFont.monospacedDigitSystemFont(ofSize: r.height * 0.56, weight: .medium)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let tw = (text as NSString).size(withAttributes: attrs).width, icon = r.height * 0.8
    let x = r.maxX - 12 - tw
    TokenPetAssets.figure(state, t: t, carrier: carrier, night: night, size: icon, menuBar: true, titles: titles)
        .draw(in: NSRect(x: x - icon - 4, y: r.midY - icon / 2, width: icon, height: icon))
    (text as NSString).draw(at: NSPoint(x: x, y: r.midY - font.pointSize * 0.62), withAttributes: attrs)
}

/// A speech bubble like the popover's, anchored at its top-right (or top-left) corner.
func bubble(_ text: String, at p: NSPoint, size: CGFloat, night: Bool, maxWidth: CGFloat, alignRight: Bool = true) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: .semibold).withDesign(.rounded),
        .foregroundColor: night ? NSColor.white : NSColor(srgbRed: 0.16, green: 0.13, blue: 0.11, alpha: 1)]
    let str = NSAttributedString(string: text, attributes: attrs)
    let b = str.boundingRect(with: NSSize(width: maxWidth - 18, height: 400), options: [.usesLineFragmentOrigin])
    let box = NSRect(x: alignRight ? p.x - b.width - 18 : p.x, y: p.y, width: ceil(b.width) + 18, height: ceil(b.height) + 12)
    NSColor.white.withAlphaComponent(night ? 0.14 : 0.82).setFill()
    NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
    str.draw(with: NSRect(x: box.minX + 9, y: box.minY + 6, width: b.width + 1, height: b.height), options: [.usesLineFragmentOrigin])
}

extension NSFont {
    func withDesign(_ d: NSFontDescriptor.SystemDesign) -> NSFont { fontDescriptor.withDesign(d).flatMap { NSFont(descriptor: $0, size: pointSize) } ?? self }
}

let sceneSize = CGSize(width: 292, height: 176), barH: CGFloat = 22

if argv.contains("--hero") {
    // Demo data, drawn by the app's own code: dig -> nearly full -> limit reached, nap -> reset -> a new title.
    struct Beat { let state: PetState; let secs: Double; let carrier: (Double, Double); let mountain: (Double, Double)
                  var night = false, tempo = Tempo.working, titles = 2, visitor: Visitor? = nil, award = false; let bar: (Double) -> String; let line: String }
    let beats = [
        Beat(state: .lively, secs: 3.2, carrier: (0.22, 0.6), mountain: (0.66, 0.63), bar: { "\(Int($0 * 100))%" },
             line: "One shovel, one shovel less mountain!"),
        Beat(state: .straining, secs: 2.6, carrier: (0.84, 0.99), mountain: (0.63, 0.61), tempo: .sweating, bar: { "\(Int($0 * 100))%" },
             line: "Oof, my back… slow down a bit?"),
        Beat(state: .resting, secs: 3.2, carrier: (1, 1), mountain: (0.61, 0.61), night: true, visitor: .zhisou, bar: { _ in "1h 58m" },
             line: "Carrier's full.\nBack to digging at 16:00"),
        Beat(state: .morning, secs: 2.2, carrier: (0, 0), mountain: (0.61, 0.61), bar: { _ in "0%" },
             line: "Morning! Shovel's waiting."),
        Beat(state: .lively, secs: 3.6, carrier: (0.04, 0.2), mountain: (0.61, 0.58), titles: 3, award: true, bar: { "\(Int($0 * 100))%" },
             line: "New title!\nStone Breaker"),
    ]
    let fps = 10.0
    var n = 0
    for b in beats {
        let frames = Int(b.secs * fps)
        for i in 0..<frames {
            let k = Double(i) / Double(max(1, frames - 1)), t = Double(i) / fps
            let carrier = b.carrier.0 + (b.carrier.1 - b.carrier.0) * k
            var info = SceneInfo(state: b.state, carrier: carrier, mountainLeft: b.mountain.0 + (b.mountain.1 - b.mountain.0) * k,
                                 grandson: nil, night: b.night)
            info.tempo = b.tempo; info.titles = b.titles; info.visitor = b.visitor
            if b.award { info.sparkle = 3 }
            let rep = bitmap(CGSize(width: sceneSize.width, height: sceneSize.height + barH), scale: 4) {
                menuBar(NSRect(x: 0, y: 0, width: sceneSize.width, height: barH), state: b.state, t: t, carrier: carrier,
                        night: b.night, titles: b.titles, text: b.bar(carrier))
                let sr = NSRect(x: 0, y: barH, width: sceneSize.width, height: sceneSize.height)
                TokenPetAssets.scene(info, t: t, size: sceneSize).draw(in: sr)
                if b.award {
                    TokenPetAssets.confetti(t: t, size: sceneSize).draw(in: sr)
                    TokenPetAssets.magpie(size: 28, t: t).draw(in: NSRect(x: 10, y: barH + 10, width: 28, height: 28 * 9 / 12))
                    bubble(b.line, at: NSPoint(x: 42, y: barH + 10), size: 12, night: false, maxWidth: 200, alignRight: false)
                } else {
                    bubble(b.line, at: NSPoint(x: sceneSize.width - 10, y: barH + 10), size: 12, night: b.night,
                           maxWidth: b.visitor != nil ? 190 : 170)
                }
            }
            try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(String(format: "hero-%03d.png", n)))
            n += 1
        }
    }
}

if argv.contains("--social") {
    // GitHub social preview: 1280x640, nothing within 40 px of an edge but the background.
    let W: CGFloat = 1280, H: CGFloat = 640
    let rep = bitmap(CGSize(width: W, height: H), scale: 1) {
        NSColor(srgbRed: 0.98, green: 0.95, blue: 0.88, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
        var info = SceneInfo(state: .lively, carrier: 0.45, mountainLeft: 0.58, grandson: nil, night: false)
        info.titles = 5
        let s: CGFloat = 2   // the scene at 2x, nearest-neighbour: 584x352 + bar
        let sw = sceneSize.width * s, sh = sceneSize.height * s, bh = barH * s
        let x = W - 64 - sw, y = (H - sh - bh) / 2
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: sw, height: sh + bh), xRadius: 28, yRadius: 28).addClip()
        menuBar(NSRect(x: x, y: y, width: sw, height: bh), state: .lively, t: 0.5, carrier: 0.45, night: false, titles: 5, text: "45%")
        TokenPetAssets.scene(info, t: 0.5, size: CGSize(width: sceneSize.width, height: sceneSize.height)).draw(in: NSRect(x: x, y: y + bh, width: sw, height: sh))
        NSGraphicsContext.restoreGraphicsState()
        let ink = NSColor(srgbRed: 0.16, green: 0.13, blue: 0.11, alpha: 1)
        func text(_ str: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, at p: NSPoint, width: CGFloat) {
            NSAttributedString(string: str, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight).withDesign(.rounded), .foregroundColor: color])
                .draw(with: NSRect(x: p.x, y: p.y, width: width, height: 400), options: [.usesLineFragmentOrigin])
        }
        let lx: CGFloat = 72, lw = x - lx - 32
        text("Token Yugong", 64, .heavy, ink, at: NSPoint(x: lx, y: 170), width: lw)
        text("愚公", 44, .bold, NSColor(srgbRed: 0.75, green: 0.28, blue: 0.23, alpha: 1), at: NSPoint(x: lx, y: 252), width: lw)
        text("Moves a mountain\none token at a time", 34, .semibold, ink.withAlphaComponent(0.85), at: NSPoint(x: lx, y: 330), width: lw)
        text("Claude Code · Codex · macOS menu bar", 22, .medium, ink.withAlphaComponent(0.55), at: NSPoint(x: lx, y: 440), width: lw)
    }
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("social-preview.png"))
}
print("wrote \(out.path)")
