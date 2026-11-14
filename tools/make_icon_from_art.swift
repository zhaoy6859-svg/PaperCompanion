import AppKit
import CoreGraphics

// Builds a macOS-style rounded icon from a square illustration.

let input = CommandLine.arguments[1]
let output = CommandLine.arguments[2]          // .iconset directory
let canvas = 1024
let margin: CGFloat = 74                        // macOS keeps artwork inset from the icon box
let content = CGFloat(canvas) - margin * 2
let radius: CGFloat = content * 0.225

guard let source = NSImage(contentsOfFile: input) else {
    FileHandle.standardError.write("cannot read \(input)\n".data(using: .utf8)!)
    exit(1)
}

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                 pixelsWide: canvas, pixelsHigh: canvas,
                                 bitsPerSample: 8, samplesPerPixel: 4,
                                 hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

// soft drop shadow like the system icons
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.30))
let square = CGRect(x: margin, y: margin, width: content, height: content)
let path = CGPath(roundedRect: square, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(path)
ctx.setFillColor(CGColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// artwork clipped to the rounded square
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let imageRect = CGRect(x: margin, y: margin, width: content, height: content)
if let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    // fill the square, preserving aspect ratio (center crop)
    let scale = max(imageRect.width / CGFloat(cg.width), imageRect.height / CGFloat(cg.height))
    let drawSize = CGSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale)
    let drawRect = CGRect(x: imageRect.midX - drawSize.width / 2,
                          y: imageRect.midY - drawSize.height / 2,
                          width: drawSize.width, height: drawSize.height)
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: drawRect)
}
ctx.restoreGState()

// subtle inner border for definition on light/dark backgrounds
ctx.addPath(path)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
ctx.setLineWidth(2)
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()

try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

let variants: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

for (dimension, name) in variants {
    guard let small = NSBitmapImageRep(bitmapDataPlanes: nil,
                                       pixelsWide: dimension, pixelsHigh: dimension,
                                       bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
    NSGraphicsContext.current?.imageInterpolation = .high
    rep.draw(in: NSRect(x: 0, y: 0, width: dimension, height: dimension))
    NSGraphicsContext.restoreGraphicsState()
    if let data = small.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
    }
}
print("icon written to \(output)")
