import AppKit
import Foundation

let size: CGFloat = CGFloat(Int(CommandLine.arguments.dropFirst().first ?? "1024") ?? 1024)
let out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func squircle(_ r: CGRect) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: r.width * 0.2237, yRadius: r.width * 0.2237)
}

/// Yıldırım — öncekinden daha dik ve daha az simetrik; ikonun köşegenine yaslanıyor.
func bolt(in box: CGRect) -> NSBezierPath {
    let w = box.width, h = box.height, x = box.minX, y = box.minY
    let p = NSBezierPath()
    p.move(to: CGPoint(x: x + w * 0.66, y: y + h * 1.00))
    p.line(to: CGPoint(x: x + w * 0.00, y: y + h * 0.42))
    p.line(to: CGPoint(x: x + w * 0.34, y: y + h * 0.42))
    p.line(to: CGPoint(x: x + w * 0.20, y: y + h * 0.00))
    p.line(to: CGPoint(x: x + w * 0.88, y: y + h * 0.58))
    p.line(to: CGPoint(x: x + w * 0.52, y: y + h * 0.58))
    p.close()
    return p
}

func glow(_ path: NSBezierPath, _ c: NSColor, radius: CGFloat, spread: Int = 3) {
    for step in stride(from: spread, through: 1, by: -1) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = c.withAlphaComponent(0.30 / CGFloat(step))
        shadow.shadowBlurRadius = radius * CGFloat(step)
        shadow.shadowOffset = .zero
        shadow.set()
        c.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Şeklin içine gölge: kenarından içeri doğru koyulaşma — oyulmuş hissi.
func innerShadow(_ path: NSBezierPath, _ rect: CGRect, _ c: NSColor,
                 blur: CGFloat, offset: NSSize) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let outside = NSBezierPath(rect: rect.insetBy(dx: -rect.width, dy: -rect.height))
    outside.append(path.reversed)
    let shadow = NSShadow()
    shadow.shadowColor = c
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
    NSColor.black.setFill()
    outside.fill()
    NSGraphicsContext.restoreGraphicsState()
}

func draw(_ name: String, _ body: (CGRect) -> Void) {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    body(CGRect(x: 0, y: 0, width: size, height: size))
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let bmp = NSBitmapImageRep(data: tiff),
          let png = bmp.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: out.appendingPathComponent("\(name).png"))
    print("→ \(name).png")
}

// ══ A · IŞIK — koyu levhadan kesilmiş yıldırım, arkasından kehribar ışık ══
draw("icon-\(Int(size))") { rect in
    let w = rect.width, h = rect.height
    squircle(rect).addClip()
    NSGradient(colors: [color(0x22222A), color(0x0C0C10)])!.draw(in: rect, angle: -90)

    let box = CGRect(x: w * 0.275, y: h * 0.16, width: w * 0.45, height: h * 0.68)
    let cut = bolt(in: box)

    glow(cut, color(0xFFB020), radius: w * 0.05, spread: 4)
    NSGraphicsContext.saveGraphicsState()
    cut.addClip()
    NSGradient(colors: [color(0xFFE27A), color(0xF09B16)])!.draw(in: box, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Kesik kenarının iç gölgesi: levhanın kalınlığı hissi.
    innerShadow(cut, rect, color(0x000000, 0.55), blur: w * 0.03,
                offset: NSSize(width: 0, height: -w * 0.012))
    // Levhanın üst kenarında ince ışık.
    NSGraphicsContext.saveGraphicsState()
    squircle(rect).addClip()
    color(0xFFFFFF, 0.07).setStroke()
    let edge = squircle(rect.insetBy(dx: w * 0.006, dy: w * 0.006))
    edge.lineWidth = w * 0.012
    edge.stroke()
    NSGraphicsContext.restoreGraphicsState()
}
