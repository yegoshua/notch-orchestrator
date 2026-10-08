// Draws the app icon, the "Keycap" of the design ("Notch Island Icons", 2a), and writes it out as
// an iconset: swift scripts/make-icon.swift <directory>.iconset. scripts/make-icon.sh turns that
// into packaging/AppIcon.icns, which is kept in the repository.
import AppKit

let amber = NSColor(srgbRed: 0xF2 / 255, green: 0xB4 / 255, blue: 0x41 / 255, alpha: 1)

func gray(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: radius, yRadius: radius)
}

/// The icon on the design's canvas of 1024, top-left origin. The small sizes leave out the fine
/// line and have a larger mark.
func draw(simple: Bool) {
    let tile = rounded(100, 100, 824, 824, 185)
    NSGradient(starting: gray(0x3A3B3E), ending: gray(0x1C1D1F))!.draw(in: tile, angle: 90)

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    gray(0x050505).setFill()
    rounded(252, 236, 520, 560, 104).fill()
    NSGradient(starting: gray(0x323232), ending: gray(0x1A1A1A))!.draw(in: rounded(280, 252, 464, 476, 86), angle: 90)
    if !simple {
        let lip = rounded(281, 253, 462, 474, 85)
        lip.lineWidth = 3
        NSColor.white.withAlphaComponent(0.14).setStroke()
        lip.stroke()
    }
    let radius: CGFloat = simple ? 84 : 66
    amber.setFill()
    NSBezierPath(ovalIn: NSRect(x: 512 - radius, y: 490 - radius, width: 2 * radius, height: 2 * radius)).fill()
    NSGraphicsContext.restoreGraphicsState()

    // The rim: lit from above, shaded below.
    let rim = rounded(102, 102, 820, 820, 183)
    rim.lineWidth = 4
    NSGraphicsContext.saveGraphicsState()
    let outline = rim.cgPath.copy(strokingWithWidth: 4, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
    NSGraphicsContext.current!.cgContext.addPath(outline)
    NSGraphicsContext.current!.cgContext.clip()
    NSGradient(colorsAndLocations:
        (NSColor.white.withAlphaComponent(0.22), 0), (NSColor.white.withAlphaComponent(0), 0.35),
        (NSColor.black.withAlphaComponent(0.25), 1))!
        .draw(in: NSRect(x: 100, y: 100, width: 824, height: 824), angle: 90)
    NSGraphicsContext.restoreGraphicsState()
}

func png(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    // The design's canvas, with its origin at the top left.
    let scale = CGFloat(pixels) / 1024
    context.cgContext.translateBy(x: 0, y: CGFloat(pixels))
    context.cgContext.scaleBy(x: scale, y: -scale)
    draw(simple: pixels <= 32)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-icon.swift <directory>.iconset\n".utf8))
    exit(1)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(pixels: points).write(to: directory.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(pixels: points * 2).write(to: directory.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
