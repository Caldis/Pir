import AppKit

enum PreferencesStyle {
    static let width: CGFloat = 450
    static let margin: CGFloat = 20
    static let labelWidth: CGFloat = 136
    static let columnSpacing: CGFloat = 15
    static let rowSpacing: CGFloat = 20
    static let checkboxHeight: CGFloat = 14
    static let descriptionSpacing: CGFloat = 6
    static let shortcutSize = NSSize(width: 140, height: 28)
    static let shortcutClearSize: CGFloat = 28
    static let shortcutClearSpacing: CGFloat = 4
    static let shortcutHelpSize: CGFloat = 16
    static let errorHeight: CGFloat = 54
    static let transitionDuration: TimeInterval = 0.3
    static let labelFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    static let controlFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    static let descriptionFont = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .mini))
    static let errorFont = NSFont.systemFont(ofSize: 11)

    static func background(height: CGFloat) -> NSVisualEffectView {
        let view = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.blendingMode = .behindWindow
        view.material = .toolTip
        view.state = .followsWindowActiveState
        return view
    }

    static func label(_ text: String, font: NSFont = controlFont, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}

enum PreferencesPage: String, CaseIterable {
    case general, pins, updates, about

    var title: String {
        switch self {
        case .general: return L("General")
        case .pins: return L("Pins")
        case .updates: return L("Updates")
        case .about: return L("About")
        }
    }

    var height: CGFloat {
        switch self {
        case .general: return 181
        case .pins: return 270
        case .updates: return 120
        case .about: return 156
        }
    }

    func contentHeight(hasError: Bool) -> CGFloat {
        height + (self == .general && hasError ? PreferencesStyle.errorHeight : 0)
    }

    var image: NSImage? {
        let image: NSImage?
        switch self {
        case .general: image = Bundle.module.url(forResource: "General", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
        case .about: image = Bundle.module.url(forResource: "About", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
        case .pins: image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: title)
        case .updates: image = Bundle.module.url(forResource: "Updates", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
        }
        image?.isTemplate = true
        image?.accessibilityDescription = title
        return image
    }
}

class PreferencesPageController: NSViewController {
    let page: PreferencesPage

    init(page: PreferencesPage) {
        self.page = page
        super.init(nibName: nil, bundle: nil)
        title = page.title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func loadView() { view = PreferencesStyle.background(height: page.height) }
}
