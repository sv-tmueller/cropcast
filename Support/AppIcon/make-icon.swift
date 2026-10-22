// Draws the CropCast app icon (1024x1024 PNG) with CoreGraphics.
// Concept: an ultrawide monitor with one 16:9 region highlighted, projected
// out as its own floating "screen" below it.
// Usage: swift make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r / 255, g / 255, b / 255, a])!
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func linear(_ colors: [CGColor], from: CGPoint, to: CGPoint, in path: CGPath) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [])
    ctx.restoreGState()
}

// Coordinates: CoreGraphics origin is bottom-left.

// 1. Background tile (macOS icon grid: 824pt body, ~185pt corner radius).
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: rgb(0, 0, 0, 0.35))
ctx.addPath(rounded(tile, 185)); ctx.setFillColor(rgb(20, 32, 70)); ctx.fillPath()
ctx.restoreGState()
linear([rgb(38, 64, 140), rgb(18, 28, 64)],
       from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100), in: rounded(tile, 185))

// 2. Ultrawide monitor (32:9-ish), upper part of the tile.
let bezel = CGRect(x: 172, y: 610, width: 680, height: 214)
ctx.addPath(rounded(bezel, 26)); ctx.setFillColor(rgb(214, 222, 236)); ctx.fillPath()
let screen = bezel.insetBy(dx: 16, dy: 16)
linear([rgb(52, 70, 112), rgb(36, 50, 86)],
       from: CGPoint(x: screen.minX, y: screen.maxY), to: CGPoint(x: screen.maxX, y: screen.minY),
       in: rounded(screen, 12))
// Faint "windows" on the ultrawide so it reads as a desktop.
let windowColor = rgb(255, 255, 255, 0.10)
for r in [CGRect(x: 204, y: 650, width: 150, height: 120),
          CGRect(x: 690, y: 640, width: 128, height: 140)] {
    ctx.addPath(rounded(r, 10)); ctx.setFillColor(windowColor); ctx.fillPath()
}

// 3. The 16:9 crop region on the ultrawide (height = screen height).
let regionH = screen.height
let region = CGRect(x: 512 - regionH * 16 / 9 / 2, y: screen.minY, width: regionH * 16 / 9, height: regionH)
ctx.addPath(rounded(region, 6)); ctx.setFillColor(rgb(150, 190, 255, 0.30)); ctx.fillPath()

// 4. Projection beams from the region down to the cast screen.
let card = CGRect(x: 232, y: 176, width: 560, height: 315)   // 16:9
ctx.saveGState()
let beam = CGMutablePath()
beam.move(to: CGPoint(x: region.minX, y: region.minY))
beam.addLine(to: CGPoint(x: region.maxX, y: region.minY))
beam.addLine(to: CGPoint(x: card.maxX, y: card.maxY))
beam.addLine(to: CGPoint(x: card.minX, y: card.maxY))
beam.closeSubpath()
linear([rgb(255, 170, 60, 0.45), rgb(255, 170, 60, 0.05)],
       from: CGPoint(x: 512, y: region.minY), to: CGPoint(x: 512, y: card.maxY), in: beam)
ctx.restoreGState()

// 5. Corner brackets marking the region (the CropCast frame).
func brackets(_ r: CGRect, length: CGFloat, width: CGFloat, color: CGColor) {
    ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    let corners: [(CGPoint, CGFloat, CGFloat)] = [
        (CGPoint(x: r.minX, y: r.minY), 1, 1), (CGPoint(x: r.maxX, y: r.minY), -1, 1),
        (CGPoint(x: r.minX, y: r.maxY), 1, -1), (CGPoint(x: r.maxX, y: r.maxY), -1, -1)]
    for (p, sx, sy) in corners {
        ctx.move(to: CGPoint(x: p.x + sx * length, y: p.y))
        ctx.addLine(to: p)
        ctx.addLine(to: CGPoint(x: p.x, y: p.y + sy * length))
    }
    ctx.strokePath()
}
brackets(region.insetBy(dx: 4, dy: 4), length: 34, width: 12, color: rgb(255, 176, 64))

// 6. The cast screen: the region as its own 16:9 display.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 0, 0, 0.45))
ctx.addPath(rounded(card, 30)); ctx.setFillColor(rgb(255, 176, 64)); ctx.fillPath()
ctx.restoreGState()
linear([rgb(255, 196, 92), rgb(246, 132, 44)],
       from: CGPoint(x: card.minX, y: card.maxY), to: CGPoint(x: card.maxX, y: card.minY),
       in: rounded(card, 30))
let cardScreen = card.insetBy(dx: 22, dy: 22)
linear([rgb(60, 82, 132), rgb(40, 56, 98)],
       from: CGPoint(x: cardScreen.minX, y: cardScreen.maxY),
       to: CGPoint(x: cardScreen.maxX, y: cardScreen.minY), in: rounded(cardScreen, 14))
// "Shared" content hint: a play-like broadcast mark (concentric arcs).
let center = CGPoint(x: cardScreen.midX - 50, y: cardScreen.midY - 50)
ctx.setStrokeColor(rgb(255, 255, 255, 0.92)); ctx.setLineCap(.round)
for (i, radius) in [CGFloat(56), 104, 152].enumerated() {
    ctx.setLineWidth(i == 0 ? 0 : 18)
    if i == 0 {
        ctx.addEllipse(in: CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44))
        ctx.setFillColor(rgb(255, 255, 255, 0.95)); ctx.fillPath()
        continue
    }
    ctx.addArc(center: center, radius: radius - 40, startAngle: .pi * 0.0, endAngle: .pi * 0.5, clockwise: false)
    ctx.strokePath()
}

guard let image = ctx.makeImage() else { fatalError() }
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
