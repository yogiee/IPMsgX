#!/usr/bin/env swift
// Builds the appiconset from a finished 1024x1024 master:
//   - sizes 32..1024 are downscaled from the master (the glass artwork)
//   - 16x16 uses a SIMPLIFIED glyph (white bubble.circle.fill on a blue squircle), since the
//     detailed master blobs out at 16px
//   - AppIcon.png (512) is exported for the Dock (used by AppIcon.swift)
// Usage: swift scripts/build-appicon.swift <master.png> <appiconset-dir> <resources-dir>

import AppKit

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write("usage: build-appicon.swift <master.png> <appiconset-dir> <resources-dir>\n".data(using: .utf8)!)
    exit(1)
}
let masterPath = args[1], iconset = args[2], resources = args[3]
guard let master = NSImage(contentsOfFile: masterPath) else {
    FileHandle.standardError.write("cannot load master: \(masterPath)\n".data(using: .utf8)!)
    exit(1)
}

func newRep(_ size: CGFloat) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

func writePNG(_ rep: NSBitmapImageRep, _ path: String) {
    if let d = rep.representation(using: .png, properties: [:]) {
        try? d.write(to: URL(fileURLWithPath: path)); print("wrote \(path)")
    }
}

/// Draw `image` into a square bitmap of `size`, high-quality.
func render(_ image: NSImage, size: CGFloat) -> NSBitmapImageRep {
    let rep = newRep(size); rep.size = NSSize(width: size, height: size)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Simplified design for tiny sizes: white bubble.circle.fill on a blue squircle.
func simplifiedDesign(_ R: CGFloat) -> NSImage {
    let space = CGColorSpaceCreateDeviceRGB()

    // White glyph, built first to avoid nested lockFocus.
    var glyph: NSImage?
    var gs = NSSize.zero
    let cfg = NSImage.SymbolConfiguration(pointSize: R * 0.72, weight: .semibold)
    if let base = NSImage(systemSymbolName: "bubble.circle.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let scale = (R * 0.72) / max(base.size.width, 1)
        gs = NSSize(width: base.size.width * scale, height: base.size.height * scale)
        let w = NSImage(size: gs); w.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: gs))
        if let wc = NSGraphicsContext.current?.cgContext { wc.setBlendMode(.sourceAtop) }
        NSColor.white.setFill(); NSRect(origin: .zero, size: gs).fill()
        w.unlockFocus(); glyph = w
    }

    let img = NSImage(size: NSSize(width: R, height: R)); img.lockFocus()
    let cg = NSGraphicsContext.current!.cgContext
    let m = R * 0.04
    let body = CGRect(x: m, y: m, width: R - 2 * m, height: R - 2 * m)
    cg.saveGState()
    NSBezierPath(roundedRect: body, xRadius: body.width * 0.2237, yRadius: body.width * 0.2237).addClip()
    let top = NSColor(red: 0.25, green: 0.58, blue: 1.0, alpha: 1).cgColor
    let bot = NSColor(red: 0.05, green: 0.34, blue: 0.88, alpha: 1).cgColor
    cg.drawLinearGradient(CGGradient(colorsSpace: space, colors: [top, bot] as CFArray, locations: [0, 1])!,
                          start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    cg.restoreGState()
    glyph?.draw(in: NSRect(x: (R - gs.width) / 2, y: (R - gs.height) / 2, width: gs.width, height: gs.height))
    img.unlockFocus()
    return img
}

for s in [32, 64, 128, 256, 512, 1024] {
    writePNG(render(master, size: CGFloat(s)), "\(iconset)/icon_\(s)x\(s).png")
}
// 16px: render the simplified design at 128 then downscale for crisp anti-aliasing.
writePNG(render(simplifiedDesign(128), size: 16), "\(iconset)/icon_16x16.png")
writePNG(render(master, size: 512), "\(resources)/AppIcon.png")
print("done")
