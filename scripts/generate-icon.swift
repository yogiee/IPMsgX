#!/usr/bin/env swift
// Generates the IPMsgX app icon — a modern macOS squircle with a messaging glyph.
// Usage: swift scripts/generate-icon.swift <appiconset-dir> <resources-dir>
//   Writes icon_NxN.png into <appiconset-dir> and AppIcon.png into <resources-dir>.

import AppKit

let args = CommandLine.arguments
let iconsetDir = args.count > 1 ? args[1] : "."
let resourcesDir = args.count > 2 ? args[2] : "."

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsctx
    let cg = nsctx.cgContext

    let S = size
    let k = S / 1024.0
    func p(_ v: CGFloat) -> CGFloat { v * k }

    // MARK: Body squircle
    let margin = p(100)
    let body = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
    let corner = body.width * 0.2237
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: corner, yRadius: corner)

    // Soft drop shadow under the squircle
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -p(16)), blur: p(40),
                 color: NSColor(white: 0, alpha: 0.30).cgColor)
    NSColor.black.setFill()
    bodyPath.fill()
    cg.restoreGState()

    // Blue gradient fill
    cg.saveGState()
    bodyPath.addClip()
    let space = CGColorSpaceCreateDeviceRGB()
    let top = NSColor(red: 0.25, green: 0.58, blue: 1.00, alpha: 1).cgColor
    let bot = NSColor(red: 0.05, green: 0.34, blue: 0.88, alpha: 1).cgColor
    let grad = CGGradient(colorsSpace: space, colors: [top, bot] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    // Subtle top sheen
    let sheen = CGGradient(colorsSpace: space,
                           colors: [NSColor(white: 1, alpha: 0.20).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray,
                           locations: [0, 1])!
    cg.drawLinearGradient(sheen, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY), options: [])
    cg.restoreGState()

    // MARK: Speech bubble glyph
    // Build the bubble + tail as ONE continuous outline so the tail flows out of the bottom
    // edge (a separate triangle overlapping the rect leaves concave notches / a "fold").
    let bubble = CGRect(x: p(248), y: p(372), width: p(528), height: p(372))
    let c = p(112)
    let minX = bubble.minX, maxX = bubble.maxX, minY = bubble.minY, maxY = bubble.maxY
    let tailLeft = p(360), tailRight = p(456), tipX = p(396), tipY = p(286)

    let bubblePath = NSBezierPath()
    bubblePath.move(to: CGPoint(x: minX, y: minY + c))
    bubblePath.appendArc(from: CGPoint(x: minX, y: minY), to: CGPoint(x: minX + c, y: minY), radius: c) // bottom-left
    bubblePath.line(to: CGPoint(x: tailLeft, y: minY))
    bubblePath.line(to: CGPoint(x: tipX, y: tipY))      // out to the tail tip
    bubblePath.line(to: CGPoint(x: tailRight, y: minY)) // back up to the bottom edge
    bubblePath.appendArc(from: CGPoint(x: maxX, y: minY), to: CGPoint(x: maxX, y: minY + c), radius: c) // bottom-right
    bubblePath.appendArc(from: CGPoint(x: maxX, y: maxY), to: CGPoint(x: maxX - c, y: maxY), radius: c) // top-right
    bubblePath.appendArc(from: CGPoint(x: minX, y: maxY), to: CGPoint(x: minX, y: maxY - c), radius: c) // top-left
    bubblePath.close()

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -p(10)), blur: p(30),
                 color: NSColor(white: 0, alpha: 0.22).cgColor)
    NSColor.white.setFill()
    bubblePath.fill()
    cg.restoreGState()

    // Three "conversation" dots inside the bubble, knocked out in blue
    let dotColor = NSColor(red: 0.11, green: 0.45, blue: 0.95, alpha: 1)
    dotColor.setFill()
    let dotR = p(42)
    let dotY = bubble.midY + p(14)
    for dx in [-p(150), CGFloat(0), p(150)] {
        let cx = bubble.midX + dx
        NSBezierPath(ovalIn: CGRect(x: cx - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2)).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("failed to encode \(path)\n".data(using: .utf8)!)
        return
    }
    try? data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

for s in [16, 32, 64, 128, 256, 512, 1024] {
    writePNG(drawIcon(size: CGFloat(s)), to: "\(iconsetDir)/icon_\(s)x\(s).png")
}
writePNG(drawIcon(size: 512), to: "\(resourcesDir)/AppIcon.png")
print("done")
