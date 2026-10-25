import AppKit
import Combine
import ServiceManagement
import PirCore

final class PreferencesModel: ObservableObject {
    let settings: SettingsStore
    let pins: PinManager
    @Published var launchAtLogin = false
    @Published var hideStatusItem: Bool
    @Published var hotKey: HotKey
    @Published var hotKeyEnabled: Bool
    @Published var error: String?
    var isRecording = false
    var onVisibilityChange: ((Bool) -> Void)?
    var onHotKeyChange: ((HotKey) throws -> Void)?
    var onHotKeyClear: (() -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    var onHotKeyDuringRecording: ((HotKey) -> Void)?
    var onShowOnboarding: (() -> Void)?

    init(settings: SettingsStore, pins: PinManager) {
        self.settings = settings
        self.pins = pins
        hideStatusItem = settings.hideStatusItem
        hotKey = settings.hotKey
        hotKeyEnabled = settings.hotKeyEnabled
        refreshLoginStatus()
    }

    func refreshLoginStatus() { launchAtLogin = SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
            if enabled, SMAppService.mainApp.status == .requiresApproval {
                error = L("Approve Pir in System Settings → General → Login Items.")
                SMAppService.openSystemSettingsLoginItems()
            } else { error = nil }
        } catch {
            refreshLoginStatus()
            self.error = L("Login item could not be changed. Move Pir to Applications and try again.")
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
            settings.hotKeyEnabled = true
            hotKey = value
            hotKeyEnabled = true
            error = nil
        } catch {
            self.error = L("Shortcut unavailable. Try another combination.")
            throw error
        }
    }

    func clearHotKey() {
        onHotKeyClear?()
        settings.hotKeyEnabled = false
        hotKeyEnabled = false
        error = nil
    }
}

