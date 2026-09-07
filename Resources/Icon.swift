import AppKit
// Standard macOS icon-size packaging of the generated master artwork.
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = NSImage(contentsOfFile: "Resources/B24Nose.png") else { fatalError("Missing B24Nose.png artwork") }
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    context.imageInterpolation = .high
    // Fit the aircraft without stretching; retain a small transparent Dock margin.
    let edge = CGFloat(size)
    let scale = edge * 0.995 / max(source.size.width, source.size.height)
    let width = source.size.width * scale, height = source.size.height * scale
    source.draw(in: NSRect(x: (edge - width) / 2, y: (edge - height) / 2, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
    context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    let name = size == 1024 ? "icon_512x512@2x.png" : "icon_\(size)x\(size).png"
    try data.write(to: destination.appendingPathComponent(name))
    if size >= 32 && size <= 512 { try data.write(to: destination.appendingPathComponent("icon_\(size / 2)x\(size / 2)@2x.png")) }
}
