import AppKit
import Combine

final class PreferencesWindowController: NSWindowController {
    let model: PreferencesModel
    private let tabs: PreferencesTabController
    private var errorObservation: AnyCancellable?

    init(model: PreferencesModel) {
        self.model = model
        tabs = PreferencesTabController(model: model)
        let size = NSSize(width: PreferencesStyle.width,
                          height: PreferencesPage.general.contentHeight(hasError: model.error != nil))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = L("Preferences")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = tabs
        tabs.onLayoutChange = { [weak self] animated in self?.resizeWindow(animated: animated) }
        resizeWindow(animated: false)
        window.center()
        errorObservation = model.$error.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.resizeWindow(animated: true)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private func resizeWindow(animated: Bool) {
        guard let window else { return }
        let height = tabs.selectedPage.contentHeight(hasError: model.error != nil)
        tabs.updatePageHeight(height)
        let chromeHeight = window.frame.height - window.contentLayoutRect.height
        var frame = NSRect(x: 0, y: 0, width: PreferencesStyle.width, height: height + chromeHeight)
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        guard frame != window.frame else { return }
        guard animated else { window.setFrame(frame, display: true); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : PreferencesStyle.transitionDuration
            window.animator().setFrame(frame, display: true)
        }
    }

    func present() {
        model.refreshLoginStatus()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class PreferencesTabController: NSTabViewController {
    private let model: PreferencesModel
    private var pageHeight: NSLayoutConstraint?
    private var backdropHeight: NSLayoutConstraint?
    var onLayoutChange: ((Bool) -> Void)?

    var selectedPage: PreferencesPage {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex),
              let identifier = tabViewItems[selectedTabViewItemIndex].identifier as? String,
              let page = PreferencesPage(rawValue: identifier) else { return .general }
        return page
    }

    init(model: PreferencesModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = []
        canPropagateSelectedChildViewControllerTitle = false
        title = L("Preferences")
        let content = NSTabView(frame: NSRect(x: 0, y: 0, width: PreferencesStyle.width, height: PreferencesPage.general.height))
        content.tabViewType = .noTabsNoBorder
        content.wantsLayer = true
        content.font = PreferencesStyle.controlFont
        tabView = content
        for page in PreferencesPage.allCases {
            let controller: PreferencesPageController
            switch page {
            case .general: controller = GeneralPreferencesController(model: model)
            case .pins: controller = PinsPreferencesController(model: model)
            case .updates: controller = UpdatesPreferencesController()
            case .about: controller = AboutPreferencesController(model: model)
            }
            let item = NSTabViewItem(viewController: controller)
            item.identifier = page.rawValue
            item.label = page.title
            item.image = page.image
            addTabViewItem(item)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func loadView() {
        super.loadView()
        let root = PreferencesContainerView(frame: NSRect(x: 0, y: 0, width: PreferencesStyle.width,
                                                         height: PreferencesPage.general.height))
        if #available(macOS 14, *) { root.clipsToBounds = false }
        tabView.removeFromSuperview()
        root.addSubview(tabView)
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // The full-window material and fixed-height page have separate layout lifetimes.
        tabView.translatesAutoresizingMaskIntoConstraints = false
        let height = tabView.heightAnchor.constraint(equalToConstant: selectedPage.contentHeight(hasError: model.error != nil))
        pageHeight = height
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tabView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabView.widthAnchor.constraint(equalToConstant: PreferencesStyle.width), height
        ])
        let background = PreferencesStyle.background(height: PreferencesPage.general.height)
        background.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(background, positioned: .below, relativeTo: tabView)
        let backdropHeight = background.heightAnchor.constraint(equalToConstant: 512)
        self.backdropHeight = backdropHeight
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: view.topAnchor),
            backdropHeight,
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        onLayoutChange?(false)
    }

    func updatePageHeight(_ height: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            pageHeight?.constant = height
            let chrome = view.window.map { $0.frame.height - $0.contentLayoutRect.height } ?? 0
            let maximum = PreferencesPage.allCases.map { $0.contentHeight(hasError: true) }.max() ?? height
            backdropHeight?.constant = maximum + chrome
            view.layoutSubtreeIfNeeded()
        }
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        onLayoutChange?(true)
    }

    override func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace] + super.toolbarDefaultItemIdentifiers(toolbar) + [.flexibleSpace]
    }

    override func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        super.toolbarAllowedItemIdentifiers(toolbar) + [.flexibleSpace]
    }
}

private final class PreferencesContainerView: NSView {
    override var isFlipped: Bool { true }

    override var frame: NSRect {
        get { super.frame }
        set {
            // NSTabViewController proposes the selected page size before NSWindow starts resizing.
            super.frame = window.map { NSRect(origin: .zero, size: $0.frame.size) } ?? newValue
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(window?.frame.size ?? newSize)
    }

    override var bounds: NSRect {
        get { super.bounds }
        set { super.bounds = window.map { NSRect(origin: .zero, size: $0.frame.size) } ?? newValue }
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(window?.frame.size ?? newSize)
    }
}
