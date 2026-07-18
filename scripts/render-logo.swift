// Renders the Context app icon + README banner.
// Usage: swift scripts/render-logo.swift <output-dir>
// Requires the Inter font family (falls back to the system font).

import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
    fputs("usage: render-logo.swift <output-dir>\n", stderr)
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let bgTop = NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.24, alpha: 1)
let bgBottom = NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.11, alpha: 1)
let accent = NSColor(calibratedRed: 0.42, green: 0.60, blue: 1.00, alpha: 1)

func interFont(size: CGFloat) -> NSFont {
    for name in ["Inter-ExtraBold", "Inter-Bold", "Inter Bold"] {
        if let f = NSFont(name: name, size: size) { return f }
    }
    return NSFont.systemFont(ofSize: size, weight: .heavy)
}

func wordmark(fontSize: CGFloat) -> NSAttributedString {
    NSAttributedString(
        string: "CONTEXT",
        attributes: [
            .font: interFont(size: fontSize),
            .foregroundColor: NSColor.white,
            .kern: fontSize * 0.14,
        ])
}

/// Draws the wordmark + accent cursor block centered at `center`, sized so the
/// whole mark fits `maxWidth`. Returns nothing; draws into the current context.
func drawMark(center: CGPoint, maxWidth: CGFloat, baseFontSize: CGFloat) {
    var fontSize = baseFontSize
    var text = wordmark(fontSize: fontSize)
    let gap = { fontSize * 0.16 }
    let cursorW = { fontSize * 0.16 }
    while text.size().width + gap() + cursorW() > maxWidth {
        fontSize *= 0.97
        text = wordmark(fontSize: fontSize)
    }
    let textSize = text.size()
    let total = textSize.width + gap() + cursorW()
    let origin = CGPoint(x: center.x - total / 2, y: center.y - textSize.height / 2)
    text.draw(at: origin)

    let capHeight = interFont(size: fontSize).capHeight
    let baseline = origin.y - interFont(size: fontSize).descender
    let cursor = NSBezierPath(
        roundedRect: NSRect(
            x: origin.x + textSize.width + gap(),
            y: baseline - capHeight * 0.02,
            width: cursorW(),
            height: capHeight * 1.04),
        xRadius: fontSize * 0.045, yRadius: fontSize * 0.045)
    accent.setFill()
    cursor.fill()
}

func render(width: Int, height: Int, draw: (CGFloat, CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(width), CGFloat(height))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to name: String) {
    let url = outDir.appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path)")
}

/// macOS-style squircle icon artwork.
func drawIcon(_ w: CGFloat, _ h: CGFloat) {
    let s = w
    let inset = s * 0.06 // Apple icon grid: artwork sits inside the canvas
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.2237
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    NSGradient(colors: [bgBottom, bgTop])!.draw(in: squircle, angle: 90)

    // Soft glow behind the wordmark.
    squircle.setClip()
    let glow = NSGradient(
        colors: [NSColor.white.withAlphaComponent(0.10), .clear])!
    glow.draw(
        fromCenter: NSPoint(x: s / 2, y: s * 0.60), radius: 0,
        toCenter: NSPoint(x: s / 2, y: s * 0.60), radius: s * 0.55, options: [])

    // Top glass highlight, fading out toward the middle (no visible seam).
    let highlight = NSGradient(
        colors: [.clear, NSColor.white.withAlphaComponent(0.10)])!
    highlight.draw(
        in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2),
        angle: 90)

    drawMark(
        center: CGPoint(x: s / 2, y: s / 2), maxWidth: rect.width * 0.80,
        baseFontSize: s * 0.12)
}

/// Transparent README banner with a dark rounded card.
func drawBanner(_ w: CGFloat, _ h: CGFloat) {
    let rect = NSRect(x: 0, y: 0, width: w, height: h)
    let card = NSBezierPath(roundedRect: rect, xRadius: h * 0.12, yRadius: h * 0.12)
    NSGradient(colors: [bgBottom, bgTop])!.draw(in: card, angle: 90)
    card.setClip()
    let highlight = NSGradient(colors: [.clear, NSColor.white.withAlphaComponent(0.08)])!
    highlight.draw(
        in: NSRect(x: 0, y: h * 0.5, width: w, height: h * 0.5), angle: 90)
    drawMark(
        center: CGPoint(x: w / 2, y: h * 0.56), maxWidth: w * 0.62,
        baseFontSize: h * 0.24)

    let subtitle = NSAttributedString(
        string: "LOCAL CHATS WITH YOUR OLLAMA MODELS",
        attributes: [
            .font: interFont(size: h * 0.045),
            .foregroundColor: NSColor.white.withAlphaComponent(0.45),
            .kern: h * 0.045 * 0.35,
        ])
    let size = subtitle.size()
    subtitle.draw(at: CGPoint(x: (w - size.width) / 2, y: h * 0.24))
}

// App icon PNGs for every .iconset slot.
for px in [16, 32, 64, 128, 256, 512, 1024] {
    write(render(width: px, height: px, draw: drawIcon), to: "icon_\(px).png")
}
// README banner (2x for retina).
write(render(width: 1600, height: 520, draw: drawBanner), to: "logo.png")
