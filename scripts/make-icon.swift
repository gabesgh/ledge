// Renders Ledge's app icon into the asset catalog.
// Usage: swift scripts/make-icon.swift Ledge/Resources/Assets.xcassets
import AppKit

let catalog = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Ledge/Resources/Assets.xcassets")
let iconSet = catalog.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    // Body, on Apple's 824pt grid with a soft drop shadow.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x1A1C23).setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0x353A48), color(0x15171D)])!.draw(in: bodyPath, angle: -90)

    // The trackpad: a pane of glass.
    let pad = NSRect(x: 212, y: 290, width: 600, height: 420)
    let padPath = NSBezierPath(roundedRect: pad, xRadius: 54, yRadius: 54)
    NSGradient(colors: [color(0x5B6173), color(0x3A3F4D)])!.draw(in: padPath, angle: -90)
    color(0xFFFFFF, 0.18).setStroke()
    padPath.lineWidth = 4
    padPath.stroke()

    // The three working edges, each with a glow.
    func strip(_ rect: NSRect, _ hex: UInt32) {
        let path = NSBezierPath(roundedRect: rect, xRadius: min(rect.width, rect.height) / 2, yRadius: min(rect.width, rect.height) / 2)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = color(hex, 0.85)
        glow.shadowBlurRadius = 34
        glow.set()
        color(hex).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    strip(NSRect(x: 760, y: 400, width: 26, height: 250), 0xFF6B38)   // volume
    strip(NSRect(x: 238, y: 400, width: 26, height: 250), 0xFFC733)   // brightness
    strip(NSRect(x: 300, y: 316, width: 424, height: 26), 0x40B8FF)   // timeline

    // A fingertip resting on the volume edge.
    let tip = NSRect(x: 728, y: 520, width: 90, height: 90)
    NSGradient(colors: [color(0xFFFFFF, 0.95), color(0xFFFFFF, 0.25)])!
        .draw(in: NSBezierPath(ovalIn: tip), relativeCenterPosition: NSPoint(x: -0.2, y: 0.25))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(points * scale).write(to: iconSet.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": ["version": 1, "author": "xcode"]], options: .prettyPrinted)
    .write(to: catalog.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(iconSet.path)")
