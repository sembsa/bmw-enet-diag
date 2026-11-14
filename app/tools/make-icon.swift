// swift tools/make-icon.swift <out.iconset> - the app icon: navy squircle, three-colour stripe, a gauge with its needle.
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let c = NSGraphicsContext.current!.cgContext
    let inset = s * 0.1, r = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let body = NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225)
    NSGraphicsContext.saveGraphicsState()
    NSShadow().then { $0.shadowBlurRadius = s * 0.02; $0.shadowOffset = NSSize(width: 0, height: -s * 0.01); $0.shadowColor = .black.withAlphaComponent(0.35) }.set()
    NSGradient(starting: NSColor(red: 0.08, green: 0.2, blue: 0.38, alpha: 1), ending: NSColor(red: 0.02, green: 0.07, blue: 0.15, alpha: 1))!
        .draw(in: body, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    body.addClip()
    // three short slanted stripes under the gauge (motorsport accent, not a progress bar)
    let colors = [NSColor(red: 0.33, green: 0.65, blue: 0.93, alpha: 1), NSColor(red: 0.11, green: 0.41, blue: 0.83, alpha: 1), NSColor(red: 0.84, green: 0.16, blue: 0.16, alpha: 1)]
    let bw = r.width * 0.07, bh = r.width * 0.2, skew = r.width * 0.06, gap = r.width * 0.025
    let x0 = s / 2 - (3 * bw + 2 * gap) / 2 - skew / 2, y0 = r.minY + r.height * 0.1
    for (i, col) in colors.enumerated() {
        let x = x0 + CGFloat(i) * (bw + gap)
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x, y: y0)); p.line(to: NSPoint(x: x + bw, y: y0))
        p.line(to: NSPoint(x: x + bw + skew, y: y0 + bh)); p.line(to: NSPoint(x: x + skew, y: y0 + bh)); p.close()
        col.setFill(); p.fill()
    }
    // gauge
    let center = CGPoint(x: s / 2, y: s * 0.53), rad = r.width * 0.3
    c.setLineCap(.round)
    c.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
    c.setLineWidth(r.width * 0.045)
    c.addArc(center: center, radius: rad, startAngle: .pi * 1.15, endAngle: -.pi * 0.15, clockwise: true)
    c.strokePath()
    c.setStrokeColor(NSColor.white.cgColor)
    c.addArc(center: center, radius: rad, startAngle: .pi * 1.15, endAngle: .pi * 0.35, clockwise: true)
    c.strokePath()
    for k in 0...8 {                                    // ticks
        let a = .pi * 1.15 - Double(k) * (.pi * 1.3 / 8)
        c.setLineWidth(r.width * 0.012)
        c.move(to: CGPoint(x: center.x + cos(a) * rad * 0.72, y: center.y + sin(a) * rad * 0.72))
        c.addLine(to: CGPoint(x: center.x + cos(a) * rad * 0.82, y: center.y + sin(a) * rad * 0.82))
        c.strokePath()
    }
    let a = Double.pi * 0.42
    c.setStrokeColor(NSColor(red: 0.95, green: 0.3, blue: 0.25, alpha: 1).cgColor)
    c.setLineWidth(r.width * 0.03)
    c.move(to: center)
    c.addLine(to: CGPoint(x: center.x + cos(a) * rad * 0.9, y: center.y + sin(a) * rad * 0.9))
    c.strokePath()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - r.width * 0.035, y: center.y - r.width * 0.035, width: r.width * 0.07, height: r.width * 0.07)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

extension NSShadow { func then(_ f: (NSShadow) -> Void) -> NSShadow { f(self); return self } }

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
