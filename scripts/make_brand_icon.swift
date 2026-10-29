import AppKit
let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let brand = try JSONSerialization.jsonObject(with: Data(contentsOf: project.appendingPathComponent("Resources/BrandMark.json"))) as! [String: Any]
let rows = (brand["rows"] as! [Int]).map(UInt16.init)
let size = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.png"
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext
context.clear(CGRect(x: 0, y: 0, width: size, height: size))
context.setFillColor(NSColor(srgbRed: 22.0 / 255, green: 75.0 / 255, blue: 1, alpha: 1).cgColor)
// Match Seal and the kit's Dock icon: 80 px outer inset, rounded 864 px tile,
// and a centered 768 px mark grid. Glyph strokes occupy two 48 px cells.
context.addPath(CGPath(roundedRect: CGRect(x: 80, y: 80, width: 864, height: 864), cornerWidth: 184, cornerHeight: 184, transform: nil))
context.fillPath()
context.setFillColor(NSColor.white.cgColor)
for (y, row) in rows.enumerated() {
    for x in 0..<16 where row & (1 << (15 - x)) != 0 {
        context.fill(CGRect(x: 128 + x * 48, y: 128 + (15 - y) * 48, width: 48, height: 48))
    }
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
