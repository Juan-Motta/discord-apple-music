// Renders the app icon into an .iconset folder; build-app.sh turns it into AppIcon.icns.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
        // macOS icon grid: the shape sits inside ~80% of the canvas.
        let inset = s * 0.1
        let shape = rect.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: shape, xRadius: shape.width * 0.225, yRadius: shape.width * 0.225)
        NSGradient(colors: [
            NSColor(srgbRed: 0.98, green: 0.24, blue: 0.40, alpha: 1),
            NSColor(srgbRed: 0.35, green: 0.40, blue: 0.95, alpha: 1),
        ])!.draw(in: path, angle: -60)

        let config = NSImage.SymbolConfiguration(pointSize: shape.width * 0.5, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        if let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        {
            let noteRect = NSRect(
                x: shape.midX - note.size.width / 2, y: shape.midY - note.size.height / 2,
                width: note.size.width, height: note.size.height)
            note.draw(in: noteRect)
        }
        return true
    }
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: output.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: output.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
