// Renders the app icon (Resources/AppIcon.icns + assets/icon.png) from code.
// Usage: swift Scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: 824pt rounded square centred in a 1024pt canvas.
    // Flat design: a priority list of three bars; the top one is "the route in use".
    let s = size / 1024
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x * s, y: y * s, width: w * s, height: h * s)
    }
    func pill(_ rect: NSRect, _ color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
    }

    let paper = NSColor(red: 0.96, green: 0.94, blue: 0.90, alpha: 1)   // warm off-white
    let ink = NSColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1)     // near black
    let signal = NSColor(red: 0.93, green: 0.33, blue: 0.18, alpha: 1)  // vermilion

    paper.setFill()
    NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s).fill()

    // Top bar (in use) with a dot marking the active device.
    pill(r(230, 600, 564, 110), signal)
    paper.setFill()
    NSBezierPath(ovalIn: r(254, 624, 62, 62)).fill()

    // Lower priorities.
    pill(r(230, 457, 420, 110), ink)
    pill(r(230, 314, 280, 110), ink.withAlphaComponent(0.35))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: CGFloat(base)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: CGFloat(base * 2)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(size: 256).write(to: URL(fileURLWithPath: "assets/icon.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print("Wrote Resources/AppIcon.icns and assets/icon.png")
