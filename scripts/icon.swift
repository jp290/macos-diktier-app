import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let size = CGFloat(pixels)
        NSColor(calibratedRed: 0.15, green: 0.39, blue: 0.70, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: size * 0.08, y: size * 0.08, width: size * 0.84, height: size * 0.84),
                     xRadius: size * 0.20, yRadius: size * 0.20).fill()
        NSColor.white.setFill()
        for (index, height) in [0.15, 0.28, 0.45, 0.62, 0.38, 0.24, 0.12].enumerated() {
            let barHeight = size * height
            NSBezierPath(roundedRect: NSRect(x: size * (0.24 + Double(index) * 0.075),
                y: (size - barHeight) / 2, width: size * 0.042, height: barHeight),
                xRadius: size * 0.021, yRadius: size * 0.021).fill()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
