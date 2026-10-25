import AppKit
import Combine

final class GeneralPreferencesController: PreferencesPageController {
    private let model: PreferencesModel
    private let launch = NSButton(checkboxWithTitle: L("Launch at login"), target: nil, action: nil)
    private let hideIcon = NSButton(checkboxWithTitle: L("Hide menu bar icon"), target: nil, action: nil)
    private let errorLabel = PreferencesStyle.label("", font: PreferencesStyle.errorFont, color: .systemRed)
    private var recorder: RecorderButton?
    private let clearShortcut = NSButton()
    private let shortcutHelp = NSButton()
    private var helpPopover: NSPopover?
    private var observation: AnyCancellable?

    init(model: PreferencesModel) {
        self.model = model
        super.init(page: .general)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func loadView() {
        super.loadView()
        let startup = rowLabel(L("Startup"))
        let status = rowLabel(L("Menu bar"))
        let shortcut = rowLabel(L("Paste shortcut"))
        let shortcutDescription = PreferencesStyle.label(L("Press the shortcut to pin the latest clipboard content to the screen."),
                                                         font: PreferencesStyle.descriptionFont, color: .secondaryLabelColor)
        shortcutDescription.lineBreakMode = .byWordWrapping
        shortcutDescription.maximumNumberOfLines = 2
        let description = PreferencesStyle.label(L("Open Puv again to restore the menu bar icon."),
                                                 font: PreferencesStyle.descriptionFont, color: .secondaryLabelColor)
        let recorder = RecorderButton(model: model)
        self.recorder = recorder
        launch.target = self
        launch.action = #selector(changeLaunch)
        hideIcon.target = self
        hideIcon.action = #selector(changeVisibility)
        for button in [launch, hideIcon] {
            button.font = PreferencesStyle.controlFont
            button.controlSize = .regular
            button.translatesAutoresizingMaskIntoConstraints = false
        }
        recorder.translatesAutoresizingMaskIntoConstraints = false
        clearShortcut.bezelStyle = .regularSquare
        clearShortcut.setButtonType(.momentaryPushIn)
        clearShortcut.image = NSImage(named: NSImage.stopProgressFreestandingTemplateName)
        clearShortcut.imagePosition = .imageOnly
        clearShortcut.target = self
        clearShortcut.action = #selector(clearHotKey)
        clearShortcut.setAccessibilityLabel(L("Clear shortcut"))
        clearShortcut.toolTip = L("Clear shortcut")
        clearShortcut.translatesAutoresizingMaskIntoConstraints = false
        shortcutHelp.bezelStyle = .helpButton
        shortcutHelp.title = ""
        shortcutHelp.target = self
        shortcutHelp.action = #selector(showShortcutHelp)
        shortcutHelp.setAccessibilityLabel(L("Supported clipboard content"))
        shortcutHelp.toolTip = L("Supported clipboard content")
        shortcutHelp.translatesAutoresizingMaskIntoConstraints = false
        description.lineBreakMode = .byWordWrapping
        description.maximumNumberOfLines = 2
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 3
        for child in [startup, status, shortcut, launch, hideIcon, description, recorder, clearShortcut,
                      shortcutHelp, shortcutDescription, errorLabel] { view.addSubview(child) }
        let preferredShortcutWidth = recorder.widthAnchor.constraint(equalToConstant: PreferencesStyle.shortcutSize.width)
        preferredShortcutWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            startup.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PreferencesStyle.margin),
            startup.widthAnchor.constraint(equalToConstant: PreferencesStyle.labelWidth),
            status.leadingAnchor.constraint(equalTo: startup.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: startup.trailingAnchor),
            shortcut.leadingAnchor.constraint(equalTo: startup.leadingAnchor),
            shortcut.trailingAnchor.constraint(equalTo: startup.trailingAnchor),
            launch.leadingAnchor.constraint(equalTo: startup.trailingAnchor, constant: PreferencesStyle.columnSpacing),
            launch.topAnchor.constraint(equalTo: view.topAnchor, constant: PreferencesStyle.margin),
            launch.heightAnchor.constraint(equalToConstant: PreferencesStyle.checkboxHeight),
            launch.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -PreferencesStyle.margin),
            startup.centerYAnchor.constraint(equalTo: launch.centerYAnchor),
            hideIcon.leadingAnchor.constraint(equalTo: launch.leadingAnchor),
            hideIcon.topAnchor.constraint(equalTo: launch.bottomAnchor, constant: PreferencesStyle.rowSpacing),
            hideIcon.heightAnchor.constraint(equalToConstant: PreferencesStyle.checkboxHeight),
            hideIcon.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -PreferencesStyle.margin),
            status.centerYAnchor.constraint(equalTo: hideIcon.centerYAnchor),
            description.leadingAnchor.constraint(equalTo: launch.leadingAnchor),
            description.topAnchor.constraint(equalTo: hideIcon.bottomAnchor, constant: PreferencesStyle.descriptionSpacing),
            description.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PreferencesStyle.margin),
            recorder.leadingAnchor.constraint(equalTo: launch.leadingAnchor),
            recorder.topAnchor.constraint(equalTo: description.bottomAnchor, constant: PreferencesStyle.rowSpacing),
            recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: PreferencesStyle.shortcutSize.width),
            preferredShortcutWidth,
            recorder.heightAnchor.constraint(equalToConstant: PreferencesStyle.shortcutSize.height),
            clearShortcut.leadingAnchor.constraint(equalTo: recorder.trailingAnchor, constant: PreferencesStyle.shortcutClearSpacing),
            clearShortcut.centerYAnchor.constraint(equalTo: recorder.centerYAnchor),
            clearShortcut.widthAnchor.constraint(equalToConstant: PreferencesStyle.shortcutClearSize),
            clearShortcut.heightAnchor.constraint(equalToConstant: PreferencesStyle.shortcutClearSize),
            shortcutHelp.leadingAnchor.constraint(equalTo: clearShortcut.trailingAnchor, constant: 6),
            shortcutHelp.centerYAnchor.constraint(equalTo: recorder.centerYAnchor),
            shortcutHelp.widthAnchor.constraint(equalToConstant: 20),
            shortcutHelp.heightAnchor.constraint(equalToConstant: 20),
            shortcut.centerYAnchor.constraint(equalTo: recorder.centerYAnchor),
            shortcutDescription.leadingAnchor.constraint(equalTo: recorder.leadingAnchor),
            shortcutDescription.trailingAnchor.constraint(equalTo: description.trailingAnchor),
            shortcutDescription.topAnchor.constraint(equalTo: recorder.bottomAnchor, constant: PreferencesStyle.descriptionSpacing),
            errorLabel.leadingAnchor.constraint(equalTo: launch.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: description.trailingAnchor),
            errorLabel.topAnchor.constraint(equalTo: shortcutDescription.bottomAnchor, constant: 12)
        ])
        synchronize()
        observation = model.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.synchronize() }
    }

    private func rowLabel(_ text: String) -> NSTextField {
        let label = PreferencesStyle.label(text, font: PreferencesStyle.labelFont, color: .secondaryLabelColor)
        label.alignment = .right
        return label
    }

    private func synchronize() {
        launch.state = model.launchAtLogin ? .on : .off
        hideIcon.state = model.hideStatusItem ? .on : .off
        recorder?.update(model.hotKey, enabled: model.hotKeyEnabled)
        clearShortcut.isEnabled = model.hotKeyEnabled
        errorLabel.stringValue = model.error ?? ""
        errorLabel.isHidden = model.error == nil
    }

    @objc private func changeLaunch() { model.setLaunchAtLogin(launch.state == .on) }
    @objc private func changeVisibility() { model.setHideStatusItem(hideIcon.state == .on) }
    @objc private func clearHotKey() { model.clearHotKey() }

    @objc private func showShortcutHelp() {
        let controller = NSViewController()
        let text = NSTextField(wrappingLabelWithString: L("Images: PNG, JPEG, TIFF and other image formats supported by macOS.\n\nText: plain text and RTF. Line breaks and indentation are preserved; rich text uses the system font and colors.\n\nCopy the image or text content itself, then press your paste shortcut."))
        text.font = .systemFont(ofSize: 12)
        text.translatesAutoresizingMaskIntoConstraints = false
        controller.view = NSView()
        controller.view.addSubview(text)
        NSLayoutConstraint.activate([
            text.widthAnchor.constraint(equalToConstant: 280),
            text.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 16),
            text.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -16),
            text.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 16),
            text.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor, constant: -16)
        ])
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        helpPopover = popover
        popover.show(relativeTo: shortcutHelp.bounds, of: shortcutHelp, preferredEdge: .maxY)
    }
}
