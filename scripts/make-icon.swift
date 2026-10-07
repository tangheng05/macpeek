// Draws the app icon into an .iconset folder for iconutil.
// Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let top = NSColor(srgbRed: 0.47, green: 0.36, blue: 1.0, alpha: 1)
let bottom = NSColor(srgbRed: 0.20, green: 0.52, blue: 0.98, alpha: 1)

/// Drawn on a 1024 grid, scaled to each size.
func draw(in size: CGFloat) {
    let s = size / 1024
    // Apple's icon grid: 824pt body, centred, with a continuous-corner feel.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: bottom, ending: top)?.draw(in: squircle, angle: 90)

    // Shield.
    let cx = 512 * s
    let shield = NSBezierPath()
    shield.move(to: NSPoint(x: cx, y: 790 * s))
    shield.curve(to: NSPoint(x: 740 * s, y: 712 * s), controlPoint1: NSPoint(x: 600 * s, y: 760 * s),
                 controlPoint2: NSPoint(x: 680 * s, y: 730 * s))
    shield.line(to: NSPoint(x: 740 * s, y: 520 * s))
    shield.curve(to: NSPoint(x: cx, y: 230 * s), controlPoint1: NSPoint(x: 740 * s, y: 380 * s),
                 controlPoint2: NSPoint(x: 640 * s, y: 280 * s))
    shield.curve(to: NSPoint(x: 284 * s, y: 520 * s), controlPoint1: NSPoint(x: 384 * s, y: 280 * s),
                 controlPoint2: NSPoint(x: 284 * s, y: 380 * s))
    shield.line(to: NSPoint(x: 284 * s, y: 712 * s))
    shield.curve(to: NSPoint(x: cx, y: 790 * s), controlPoint1: NSPoint(x: 344 * s, y: 730 * s),
                 controlPoint2: NSPoint(x: 424 * s, y: 760 * s))
    shield.close()
    NSColor.white.withAlphaComponent(0.95).setFill()
    shield.fill()

    // Three meter bars inside the shield.
    let heights: [CGFloat] = [120, 210, 160]
    for (index, height) in heights.enumerated() {
        let x = (402 + CGFloat(index) * 80) * s
        let bar = NSRect(x: x, y: 420 * s, width: 60 * s, height: height * s)
        let path = NSBezierPath(roundedRect: bar, xRadius: 18 * s, yRadius: 18 * s)
        NSGradient(starting: bottom, ending: top)?.draw(in: path, angle: 90)
    }
}

func png(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(in: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try png(pixels: points * scale)?.write(to: output.appending(path: name))
    }
}
