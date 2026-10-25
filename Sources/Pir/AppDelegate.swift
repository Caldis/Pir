import AppKit
import Carbon
import PirCore

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
        model.onHotKeyClear = { [weak self] in self?.hotKey.clear() }
        model.onRecordingChange = { [weak self] active in self?.hotKeyBackend.isRecording = active }
        model.onShowOnboarding = { [weak self] in self?.showOnboarding() }
        return model
    }()
    private lazy var preferences = PreferencesWindowController(model: preferencesModel)
    private var feedback: FeedbackPanel?
    private var onboarding: OnboardingWindowController?
    private lazy var onboardingDemo = OnboardingDemoController(pins: pins)

    func applicationDidFinishLaunching(_ notification: Notification) {
        pins.onPersistenceFailure = { [weak self] in self?.showFeedback(L("Pins could not be saved. Check available disk space.")) }
        pins.restoreSession()
        Task { @MainActor in UpdateManager.shared.scheduleCheckOnAppStartIfNeeded() }
        installMainMenu()
        updateStatusItem(hidden: settings.hideStatusItem)
        hotKeyBackend.onPress = { [weak self] in self?.paste() }
        hotKeyBackend.onPressWhileRecording = { [weak self] key in
            self?.preferencesModel.onHotKeyDuringRecording?(key)
        }
        do { if settings.hotKeyEnabled { try hotKey.replace(with: settings.hotKey) } }
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
            let controller = OnboardingWindowController(settings: settings, model: preferencesModel)
            controller.onTryShortcut = { [weak self] screen in
                guard let self else { return false }
                do { try self.onboardingDemo.showLogo(on: screen); return true }
                catch { self.preferencesModel.error = L("Close a pin before adding another."); return false }
            }
            controller.onFinish = { [weak self] in
                self?.onboardingDemo.stopCelebration()
                self?.preferences.present()
            }
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
            ?? NSImage(systemSymbolName: "p.circle", accessibilityDescription: "Pir")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "Pir"
        item.button?.setAccessibilityLabel("Pir")
        let menu = NSMenu()
        menu.addItem(withTitle: L("Preferences") + "…", action: #selector(showPreferences), keyEquivalent: ",").target = self
        menu.addItem(withTitle: L("Quit Pir"), action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    private func installMainMenu() {
        let main = NSMenu()
        let item = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(withTitle: L("Preferences") + "…", action: #selector(showPreferences), keyEquivalent: ",").target = self
        submenu.addItem(withTitle: L("Quit Pir"), action: #selector(quit), keyEquivalent: "q").target = self
        item.submenu = submenu
        main.addItem(item)
        let edit = NSMenu(title: L("Edit"))
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
                                      ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                      ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            let command = NSMenuItem(title: L(title), action: Selector(selector), keyEquivalent: key.lowercased())
            command.keyEquivalentModifierMask = key == "Z" ? [.command, .shift] : [.command]
            edit.addItem(command)
        }
        let editItem = NSMenuItem(title: L("Edit"), action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func showPreferences() { preferences.present() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func paste() {
        if onboarding?.window?.isVisible == true {
            onboarding?.tryShortcut()
            return
        }
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
        onboardingDemo.stopCelebration()
        hotKey.clear()
        pins.flushSession()
        pins.closeAll()
        feedback?.close()
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
