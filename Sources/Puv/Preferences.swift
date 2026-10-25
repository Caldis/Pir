import AppKit
import ServiceManagement
import SwiftUI
import PuvCore

final class PreferencesModel: ObservableObject {
    let settings: SettingsStore
    let pins: PinManager
    @Published var launchAtLogin = false
    @Published var hideStatusItem: Bool
    @Published var hotKey: HotKey
    @Published var error: String?
    var onVisibilityChange: ((Bool) -> Void)?
    var onHotKeyChange: ((HotKey) throws -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    var onShowOnboarding: (() -> Void)?

    init(settings: SettingsStore, pins: PinManager) {
        self.settings = settings
        self.pins = pins
        hideStatusItem = settings.hideStatusItem
        hotKey = settings.hotKey
        refreshLoginStatus()
    }

    func refreshLoginStatus() { launchAtLogin = SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
            if enabled, SMAppService.mainApp.status == .requiresApproval {
                error = L("Approve Puv in System Settings → General → Login Items.")
                SMAppService.openSystemSettingsLoginItems()
            } else { error = nil }
        } catch {
            refreshLoginStatus()
            self.error = L("Login item could not be changed. Move Puv to Applications and try again.")
        }
    }

    func setHideStatusItem(_ hidden: Bool) {
        settings.hideStatusItem = hidden
        hideStatusItem = hidden
        onVisibilityChange?(hidden)
    }

    func setHotKey(_ value: HotKey) throws {
        do {
            try onHotKeyChange?(value)
            settings.hotKey = value
            hotKey = value
            error = nil
        } catch {
            self.error = L("Shortcut unavailable. Try another combination.")
            throw error
        }
    }
}

private enum PreferencesPage: String, CaseIterable {
    case general, pins, about
    var title: String {
        switch self {
        case .general: return L("General")
        case .pins: return L("Pins")
        case .about: return L("About")
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .pins: return "square.on.square"
        case .about: return "info.circle"
        }
    }
    var height: CGFloat {
        switch self {
        case .general: return 170
        case .pins: return 270
        case .about: return 245
        }
    }
    var identifier: NSToolbarItem.Identifier { .init(rawValue) }
}

final class PreferencesWindowController: NSWindowController, NSToolbarDelegate {
    let model: PreferencesModel
    private let navigation = PreferencesNavigation()

    init(model: PreferencesModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 170),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("Preferences")
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: PreferencesView(model: model, navigation: navigation))
        let toolbar = NSToolbar(identifier: "PuvPreferences")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.sizeMode = .small
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar
        toolbar.selectedItemIdentifier = PreferencesPage.general.identifier
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        PreferencesPage.allCases.map(\.identifier)
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let page = PreferencesPage(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = page.title
        item.paletteLabel = page.title
        item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.title)
        item.target = self
        item.action = #selector(selectPage(_:))
        return item
    }

    @objc private func selectPage(_ sender: NSToolbarItem) {
        guard let page = PreferencesPage(rawValue: sender.itemIdentifier.rawValue), let window else { return }
        navigation.page = page
        window.title = L("Preferences")
        window.toolbar?.selectedItemIdentifier = page.identifier
        let oldTop = window.frame.maxY
        window.setContentSize(NSSize(width: 450, height: page.height))
        var frame = window.frame
        frame.origin.y = oldTop - frame.height
        window.setFrame(frame, display: true, animate: true)
    }

    func present() {
        model.refreshLoginStatus()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private final class PreferencesNavigation: ObservableObject {
    @Published var page: PreferencesPage = .general
}

private struct PreferencesView: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var navigation: PreferencesNavigation

    var body: some View {
        Group {
            switch navigation.page {
            case .general: general
            case .pins: PinsPreferencesView(manager: model.pins)
            case .about: about
            }
        }
        .frame(width: 450, height: navigation.page.height)
        .font(.system(size: 13))
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingRow(L("Startup")) {
                Toggle(L("Launch at login"), isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                    .toggleStyle(.checkbox).controlSize(.regular)
            }
            settingRow(L("Menu bar")) {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle(L("Hide menu bar icon"), isOn: Binding(get: { model.hideStatusItem }, set: model.setHideStatusItem))
                        .toggleStyle(.checkbox).controlSize(.regular)
                    Text(L("Open Puv again to restore the menu bar icon."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            settingRow(L("Shortcut")) {
                HotKeyControl(model: model).frame(width: 166, height: 30)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28).padding(.top, 18)
        .overlay(alignment: .bottom) {
            if let error = model.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 28).padding(.bottom, 6)
            }
        }
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(label).foregroundStyle(.secondary).frame(width: 68, alignment: .trailing).padding(.top, 2)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var about: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable().frame(width: 64, height: 64)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("Puv").font(.system(size: 24, weight: .semibold))
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                    .foregroundStyle(.secondary).font(.system(size: 12))
            }
            Text(L("Keep a thought in sight.")).font(.system(size: 13))
            HStack(spacing: 20) {
                Link(L("Website"), destination: URL(string: "https://caldis.github.io/Puv/")!)
                Link(L("Source code"), destination: URL(string: "https://github.com/Caldis/Puv")!)
                Button(L("Welcome to Puv")) { model.onShowOnboarding?() }.buttonStyle(.link)
            }.padding(.top, 4)
            Link(L("License"), destination: URL(string: "https://github.com/Caldis/Puv/blob/main/LICENSE")!)
                .font(.system(size: 11))
        }.padding(22)
    }
}

private struct PinsPreferencesView: View {
    @ObservedObject var manager: PinManager

    var body: some View {
        Group {
            if manager.summaries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.on.square").font(.system(size: 28, weight: .light)).foregroundStyle(.tertiary)
                    Text(L("No pins yet")).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(manager.summaries) { pin in
                            pinRow(pin)
                            if pin.id != manager.summaries.last?.id { Divider().padding(.leading, 52) }
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 8)
                }
            }
        }
    }

    private func pinRow(_ pin: PinSummary) -> some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail = pin.thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                } else {
                    Image(systemName: pin.kind == .image ? "photo" : "text.alignleft")
                        .font(.system(size: 17)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.quaternary.opacity(0.45))
                }
            }.frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(pin.title).lineLimit(1).foregroundStyle(pin.isHidden ? .secondary : .primary)
                Text(L(pin.kind == .image ? "Image" : "Text"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Button {
                manager.setHidden(!pin.isHidden, for: pin.id)
            } label: {
                Image(systemName: pin.isHidden ? "eye.slash" : "eye")
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.borderless)
            .help(L(pin.isHidden ? "Show pin" : "Hide pin"))
            .accessibilityLabel(L(pin.isHidden ? "Show pin" : "Hide pin"))
            Button(role: .destructive) { manager.delete(pin.id) } label: {
                Image(systemName: "trash").frame(width: 24, height: 28)
            }
            .buttonStyle(.borderless).help(L("Delete pin")).accessibilityLabel(L("Delete pin"))
        }.padding(.vertical, 9)
    }
}

private struct HotKeyControl: NSViewRepresentable {
    @ObservedObject var model: PreferencesModel
    func makeNSView(context: Context) -> RecorderButton { RecorderButton(model: model) }
    func updateNSView(_ view: RecorderButton, context: Context) { view.update(model.hotKey) }
}

private final class RecorderButton: NSButton {
    private let preview = KeyPreview()
    private let recorder = KeyRecorder()
    private let model: PreferencesModel

    init(model: PreferencesModel) {
        self.model = model
        super.init(frame: .zero)
        bezelStyle = .rounded
        title = ""
        target = self
        action = #selector(record)
        setAccessibilityLabel(L("Record paste shortcut"))
        toolTip = L("Click, then press a key combination. Escape cancels.")
        addSubview(preview)
        NSLayoutConstraint.activate([preview.centerXAnchor.constraint(equalTo: centerXAnchor),
                                     preview.centerYAnchor.constraint(equalTo: centerYAnchor)])
        preview.setAccessibilityElement(false)
        recorder.onRecord = { [weak model] value in try model?.setHotKey(value) }
        recorder.onStateChange = { [weak model] active in model?.onRecordingChange?(active) }
        update(model.hotKey)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func update(_ value: HotKey) {
        preview.update(from: value.displayComponents)
        setAccessibilityValue(value.displayComponents.joined(separator: " + "))
    }
    @objc private func record() { recorder.start(from: self) }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { recorder.stop() }
    }
}
