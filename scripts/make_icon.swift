import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

for size in [16, 32, 64, 128, 256, 512, 1024] {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Icon context failed") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964), xRadius: 210, yRadius: 210)
    NSColor(calibratedRed: 0.09, green: 0.06, blue: 0.085, alpha: 1).setFill()
    background.fill()
    let gauge = NSBezierPath()
    gauge.appendArc(withCenter: NSPoint(x: 512, y: 490), radius: 338, startAngle: 18, endAngle: 162)
    gauge.lineWidth = 49
    gauge.lineCapStyle = .round
    NSColor(calibratedRed: 1, green: 0.35, blue: 0.18, alpha: 1).setStroke()
    gauge.stroke()
    let needle = NSBezierPath()
    needle.move(to: NSPoint(x: 512, y: 490))
    needle.line(to: NSPoint(x: 695, y: 680))
    needle.lineWidth = 31
    needle.lineCapStyle = .round
    NSColor(calibratedRed: 0.98, green: 0.85, blue: 0.68, alpha: 1).setStroke()
    needle.stroke()
    let text = "B!" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 265, weight: .heavy),
        .foregroundColor: NSColor(calibratedRed: 0.98, green: 0.92, blue: 0.86, alpha: 1)]
    let bounds = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: (1024 - bounds.width) / 2, y: 215), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon render failed") }
    var names: [String] = []
    if [16, 32, 128, 256, 512].contains(size) { names.append("icon_\(size)x\(size).png") }
    if [16, 32, 128, 256, 512].contains(size / 2) { names.append("icon_\(size / 2)x\(size / 2)@2x.png") }
    for name in names { try png.write(to: directory.appendingPathComponent(name)) }
}
