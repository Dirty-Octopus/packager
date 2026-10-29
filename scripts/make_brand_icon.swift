import AppKit
let size = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.png"
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext
context.setFillColor(NSColor(srgbRed: 22.0 / 255, green: 75.0 / 255, blue: 1, alpha: 1).cgColor)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setFillColor(NSColor.white.cgColor)
let rows: [UInt16] = [0, 0, 0, 0x1ff0, 0x1018, 0x1018, 0x1018, 0x1ff0, 0x1000, 0x1000, 0x1000, 0x1000, 0x1000, 0, 0, 0]
for (y, row) in rows.enumerated() {
    for x in 0..<16 where row & (1 << (15 - x)) != 0 {
        context.fill(CGRect(x: x * 64, y: (15 - y) * 64, width: 64, height: 64))
    }
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
