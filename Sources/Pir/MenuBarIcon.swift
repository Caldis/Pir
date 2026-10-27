import AppKit

enum MenuBarIcon {
    static func image(in bundle: Bundle = .main) -> NSImage? {
        let image = bundle.image(forResource: "MenuBarTemplate")
            ?? NSImage(systemSymbolName: "p.circle", accessibilityDescription: "Pir")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        return image
    }
}
