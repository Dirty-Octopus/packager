import AppKit

// Renders the exact in-app BrandMark as the 1024 px application icon.
let renderSize = 2048
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.png"

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: renderSize,
    pixelsHigh: renderSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { fatalError("bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("context") }

let s = CGFloat(renderSize)
let rect = CGRect(x: 0, y: 0, width: s, height: s)
ctx.clear(rect)

let radius = s * 0.26
let tile = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.addPath(tile)
ctx.clip()

let colors = [
    NSColor(srgbRed: 0x6A / 255, green: 0x4B / 255, blue: 0xF2 / 255, alpha: 1).cgColor,
    NSColor(srgbRed: 0x8E / 255, green: 0x6B / 255, blue: 0xFF / 255, alpha: 1).cgColor,
    NSColor(srgbRed: 0xB1 / 255, green: 0x83 / 255, blue: 0xFF / 255, alpha: 1).cgColor
]
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.52, 1])!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: s),
    end: CGPoint(x: s, y: 0),
    options: []
)

// Soft top-left light, matching the in-app tile.
let glow = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor.white.withAlphaComponent(0.16).cgColor,
        NSColor.white.withAlphaComponent(0).cgColor
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: s * 0.16, y: s * 0.84),
    startRadius: 0,
    endCenter: CGPoint(x: s * 0.16, y: s * 0.84),
    endRadius: s * 0.7,
    options: []
)

ctx.restoreGState()

// Inner hairline, like the BrandMark stroke.
ctx.addPath(tile)
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
ctx.setLineWidth(s * 0.002)
ctx.strokePath()

// White shippingbox glyph.
let pointSize = s * 0.45
let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
guard let symbol = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config),
      let symbolCG = symbol.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { fatalError("symbol") }

let glyphSize = CGSize(width: CGFloat(symbolCG.width), height: CGFloat(symbolCG.height))
let scaled = CGSize(
    width: pointSize * 1.0,
    height: pointSize * (glyphSize.height / glyphSize.width)
)
let glyphRect = CGRect(
    x: (s - scaled.width) / 2,
    y: (s - scaled.height) / 2 - s * 0.004,
    width: scaled.width,
    height: scaled.height
)

ctx.saveGState()
ctx.clip(to: glyphRect, mask: symbolCG)
ctx.setFillColor(NSColor.white.withAlphaComponent(0.97).cgColor)
ctx.fill(glyphRect)
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("png") }
try data.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath) (\(bitmap.pixelsWide)x\(bitmap.pixelsHigh))")
