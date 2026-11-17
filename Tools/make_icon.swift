// Рисует иконку (четыре плитки в стиле «Пуск») и собирает AppIcon.iconset
// Использование: make_icon <папка-вывода>
import Cocoa

func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let k = CGFloat(size) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: k, y: k)

    // белая плашка
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                            xRadius: 185, yRadius: 185)
    NSGradient(colors: [NSColor(white: 0.93, alpha: 1),
                        NSColor(white: 1.0, alpha: 1)])!
        .draw(in: body, angle: 90)

    // четыре плитки «Пуск» с синим градиентом
    let tile: CGFloat = 218, gap: CGFloat = 24
    let total = tile * 2 + gap
    let x0 = (1024 - total) / 2, y0 = (1024 - total) / 2
    for i in 0..<2 {
        for j in 0..<2 {
            let r = NSRect(x: x0 + CGFloat(i) * (tile + gap), y: y0 + CGFloat(j) * (tile + gap),
                           width: tile, height: tile)
            let path = NSBezierPath(roundedRect: r, xRadius: 16, yRadius: 16)
            NSGradient(colors: [NSColor(red: 0.00, green: 0.47, blue: 0.83, alpha: 1),
                                NSColor(red: 0.30, green: 0.76, blue: 1.00, alpha: 1)])!
                .draw(in: path, angle: 90)
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let set = out.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
let files: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)]
for (name, px) in files {
    try render(px).write(to: set.appendingPathComponent(name + ".png"))
}
