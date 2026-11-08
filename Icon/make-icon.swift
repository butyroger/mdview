// 產生 MDView 圖示：swift make-icon.swift → AppIcon.iconset → iconutil
import AppKit

func draw(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)
    // macOS 圖示格線：824×824 圓角方塊置中，含陰影
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.28); sh.shadowBlurRadius = 28; sh.shadowOffset = NSSize(width: 0, height: -12); sh.set()
    NSColor.black.setFill(); squircle.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.42, blue: 0.98, alpha: 1), NSColor(srgbRed: 0.52, green: 0.25, blue: 0.86, alpha: 1)])!
        .draw(in: squircle, angle: -60)
    // 白色文件＋摺角
    let doc = NSRect(x: 262, y: 200, width: 500, height: 624), fold: CGFloat = 130
    let page = NSBezierPath()
    page.move(to: NSPoint(x: doc.minX + 36, y: doc.minY))
    page.line(to: NSPoint(x: doc.maxX - 36, y: doc.minY))
    page.curve(to: NSPoint(x: doc.maxX, y: doc.minY + 36), controlPoint1: NSPoint(x: doc.maxX - 16, y: doc.minY), controlPoint2: NSPoint(x: doc.maxX, y: doc.minY + 16))
    page.line(to: NSPoint(x: doc.maxX, y: doc.maxY - fold))
    page.line(to: NSPoint(x: doc.maxX - fold, y: doc.maxY))
    page.line(to: NSPoint(x: doc.minX + 36, y: doc.maxY))
    page.curve(to: NSPoint(x: doc.minX, y: doc.maxY - 36), controlPoint1: NSPoint(x: doc.minX + 16, y: doc.maxY), controlPoint2: NSPoint(x: doc.minX, y: doc.maxY - 16))
    page.line(to: NSPoint(x: doc.minX, y: doc.minY + 36))
    page.curve(to: NSPoint(x: doc.minX + 36, y: doc.minY), controlPoint1: NSPoint(x: doc.minX, y: doc.minY + 16), controlPoint2: NSPoint(x: doc.minX + 16, y: doc.minY))
    page.close()
    NSGraphicsContext.saveGraphicsState()
    let sh2 = NSShadow(); sh2.shadowColor = NSColor.black.withAlphaComponent(0.22); sh2.shadowBlurRadius = 18; sh2.shadowOffset = NSSize(width: 0, height: -8); sh2.set()
    NSColor.white.setFill(); page.fill()
    NSGraphicsContext.restoreGraphicsState()
    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: doc.maxX - fold, y: doc.maxY))
    corner.line(to: NSPoint(x: doc.maxX - fold, y: doc.maxY - fold + 24))
    corner.curve(to: NSPoint(x: doc.maxX - fold + 24, y: doc.maxY - fold), controlPoint1: NSPoint(x: doc.maxX - fold, y: doc.maxY - fold + 8), controlPoint2: NSPoint(x: doc.maxX - fold + 8, y: doc.maxY - fold))
    corner.line(to: NSPoint(x: doc.maxX, y: doc.maxY - fold))
    corner.close()
    NSColor(srgbRed: 0.80, green: 0.83, blue: 0.95, alpha: 1).setFill(); corner.fill()
    // 文字行
    NSColor(srgbRed: 0.84, green: 0.86, blue: 0.93, alpha: 1).setFill()
    for (y, w) in [(700.0, 230.0), (650.0, 300.0)] { NSBezierPath(roundedRect: NSRect(x: 322, y: y, width: w, height: 22), xRadius: 11, yRadius: 11).fill() }
    // Markdown 標誌：M ＋ ↓
    let ink = NSColor(srgbRed: 0.28, green: 0.25, blue: 0.62, alpha: 1)
    ink.setStroke(); ink.setFill()
    let m = NSBezierPath(); m.lineWidth = 48; m.lineJoinStyle = .round; m.lineCapStyle = .round
    m.move(to: NSPoint(x: 340, y: 300)); m.line(to: NSPoint(x: 340, y: 540)); m.line(to: NSPoint(x: 420, y: 440))
    m.line(to: NSPoint(x: 500, y: 540)); m.line(to: NSPoint(x: 500, y: 300)); m.stroke()
    let shaft = NSBezierPath(); shaft.lineWidth = 48; shaft.lineCapStyle = .round
    shaft.move(to: NSPoint(x: 625, y: 540)); shaft.line(to: NSPoint(x: 625, y: 390)); shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 545, y: 400)); head.line(to: NSPoint(x: 705, y: 400)); head.line(to: NSPoint(x: 625, y: 290)); head.close()
    head.lineJoinStyle = .round; head.lineWidth = 16; head.fill(); head.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dir = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for (pt, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for sc in scales {
        let name = "icon_\(pt)x\(pt)" + (sc == 2 ? "@2x" : "") + ".png"
        try! draw(pt * sc).representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
    }
}
try! draw(1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon-1024.png"))
