import AppKit
import TokenPetAssets

// Renders Grandpa Yugong's character sheets as PNG (both styles) and vector PDF (both; the ink
// page is fully vector, the pixel page embeds its sprites as bitmaps).
// usage: YugongSheet <out-dir> [--crop x,y,w,h]   (crop writes extra zoomed review images)
let argv = CommandLine.arguments
let out = URL(fileURLWithPath: argv.count > 1 ? argv[1] : ".")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let size = YugongSheet.pageSize

func renderPNG(_ style: ArtStyle) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    // y-down page
    g.cgContext.translateBy(x: 0, y: size.height); g.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: g.cgContext, flipped: true)
    NSGraphicsContext.current?.imageInterpolation = .none
    YugongSheet.drawSheet(style)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func renderPDF(_ style: ArtStyle, _ url: URL) {
    var box = CGRect(origin: .zero, size: size)
    guard let c = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
    c.beginPDFPage(nil)
    c.translateBy(x: 0, y: size.height); c.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
    YugongSheet.drawSheet(style)
    NSGraphicsContext.restoreGraphicsState()
    c.endPDFPage(); c.closePDF()
}

for s in ArtStyle.allCases {
    let rep = renderPNG(s)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("yugong-sheet-\(s.rawValue).png"))
    renderPDF(s, out.appendingPathComponent("yugong-sheet-\(s.rawValue).pdf"))
    if let i = argv.firstIndex(of: "--crop"), i + 1 < argv.count {
        let v = argv[i + 1].split(separator: ",").compactMap { Int($0) }
        if v.count == 4, let cg = rep.cgImage?.cropping(to: CGRect(x: v[0], y: v[1], width: v[2], height: v[3])) {
            try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
                .write(to: out.appendingPathComponent("crop-\(s.rawValue).png"))
        }
    }
}
if let i = argv.firstIndex(of: "--frames"), i + 1 < argv.count, let st = PetState(flag: argv[i + 1]) {
    let img = YugongSheet.frames(.pixel, st, fps: 6, night: argv.contains("--night"))
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("frames-\(st.rawValue).png"))
}
if argv.contains("--scenes") {
    for s in ArtStyle.allCases {
        let img = YugongSheet.sceneStrip(s)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(img.size.width * 2), pixelsHigh: Int(img.size.height * 2), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = img.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .none
        img.draw(in: NSRect(origin: .zero, size: img.size))
        NSGraphicsContext.restoreGraphicsState()
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("scenes-\(s.rawValue).png"))
    }
}
print("wrote \(out.path)")
