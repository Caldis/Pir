import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("assets/brand")
guard let image = NSImage(contentsOf: assets.appendingPathComponent("MenuBarTemplate.svg")) else {
    fatalError("Run from the project root with MenuBarTemplate.svg present")
}
for scale in [1, 2] {
    let pixels = 18 * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: 18, height: 18)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "MenuBarTemplate.png" : "MenuBarTemplate@2x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: assets.appendingPathComponent(name))
}
