import AppKit
import Carbon
import PuvCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let hotKeyBackend = GlobalHotKey()
    private lazy var hotKey = HotKeyBinding(backend: hotKeyBackend)
    private let pins = PinManager()
    private var statusItem: NSStatusItem?
    private lazy var preferencesModel: PreferencesModel = {
        let model = PreferencesModel(settings: settings, pins: pins)
        model.onVisibilityChange = { [weak self] hidden in self?.updateStatusItem(hidden: hidden) }
        model.onHotKeyChange = { [weak self] value in try self?.hotKey.replace(with: value) }
        model.onRecordingChange = { [weak self] active in self?.hotKeyBackend.isRecording = active }
        model.onShowOnboarding = { [weak self] in self?.showOnboarding() }
        return model
    }()
    private lazy var preferences = PreferencesWindowController(model: preferencesModel)
    private var feedback: FeedbackPanel?
    private var onboarding: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        pins.onPersistenceFailure = { [weak self] in self?.showFeedback(L("Pins could not be saved. Check available disk space.")) }
        pins.restoreSession()
        installMainMenu()
        updateStatusItem(hidden: settings.hideStatusItem)
        hotKeyBackend.onPress = { [weak self] in self?.paste() }
        do { try hotKey.replace(with: settings.hotKey) }
        catch {
            preferencesModel.error = L("Shortcut unavailable. Try another combination.")
        }
        // Login launches stay quiet; an explicit launch exposes the settings entry point.
        let launchData = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)
        let loginLaunch = launchData?.enumCodeValue == keyAELaunchedAsLogInItem
        if !loginLaunch {
            if settings.hideStatusItem { preferencesModel.setHideStatusItem(false) }
            presentLaunchWindow()
        }
    }

    private func presentLaunchWindow() {
        if settings.hasCompletedOnboarding { preferences.present() }
        else { showOnboarding() }
    }

    private func showOnboarding() {
        preferences.close()
        if onboarding == nil {
            let controller = OnboardingWindowController(settings: settings)
            controller.onFinish = { [weak self] in self?.preferences.present() }
            onboarding = controller
        }
        onboarding?.present()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        preferencesModel.setHideStatusItem(false)
        presentLaunchWindow()
        return true
    }

    private func updateStatusItem(hidden: Bool) {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        guard !hidden else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = Bundle.main.url(forResource: "MenuBarTemplate", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "p.circle", accessibilityDescription: "Puv")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "Puv"
        item.button?.setAccessibilityLabel("Puv")
        let menu = NSMenu()
        menu.addItem(withTitle: L("Preferences") + "…", action: #selector(showPreferences), keyEquivalent: ",").target = self
        menu.addItem(withTitle: L("Quit Puv"), action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    private func installMainMenu() {
        let main = NSMenu()
        let item = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(withTitle: L("Preferences") + "…", action: #selector(showPreferences), keyEquivalent: ",").target = self
        submenu.addItem(withTitle: L("Quit Puv"), action: #selector(quit), keyEquivalent: "q").target = self
        item.submenu = submenu
        main.addItem(item)
        NSApp.mainMenu = main
    }

    @objc private func showPreferences() { preferences.present() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func paste() {
        do { try pins.show(ClipboardReader.read()) }
        catch ClipboardError.tooLarge { showFeedback(L("Clipboard content is too large.")) }
        catch PinManager.PinError.limit { showFeedback(L("Close a pin before adding another.")) }
        catch { showFeedback(L("Copy an image or text, then try again.")) }
    }

    private func showFeedback(_ message: String) {
        feedback?.close()
        let panel = FeedbackPanel(message: message)
        feedback = panel
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak panel] in
            panel?.close()
            if self?.feedback === panel { self?.feedback = nil }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.clear()
        pins.flushSession()
        pins.closeAll()
        feedback?.close()
        onboarding?.stopPermissionGuidance()
    }
}

private final class FeedbackPanel: NSPanel {
    init(message: String) {
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13)
        label.alignment = .center
        let size = NSSize(width: min(600, max(260, label.intrinsicContentSize.width + 40)), height: 52)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        super.init(contentRect: NSRect(x: screen.midX - size.width / 2, y: screen.minY + 80,
                                      width: size.width, height: size.height),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        label.frame = NSRect(x: 20, y: 17, width: size.width - 40, height: 18)
        background.addSubview(label)
        contentView = background
        setAccessibilityLabel(message)
    }
}
