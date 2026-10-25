import AppKit
import ApplicationServices
import PermissionFlow
import SwiftUI
import PuvCore

@MainActor
final class AccessibilityGuide: ObservableObject {
    @Published private(set) var isGranted = AXIsProcessTrusted()
    private let controller = PermissionFlow.makeController(configuration: .init(
        requiredAppURLs: [Bundle.main.bundleURL],
        promptForAccessibilityTrust: false,
        localeIdentifier: Locale.preferredLanguages.first
    ))
    private var timer: Timer?
    private var deadline: Date?
    private var observedSettingsRunning = false

    func refresh() {
        isGranted = AXIsProcessTrusted()
        if isGranted { close() }
    }

    func authorize() {
        refresh()
        guard !isGranted else { return }
        let point = NSEvent.mouseLocation
        controller.authorize(pane: .accessibility, suggestedAppURLs: [Bundle.main.bundleURL],
                             sourceFrameInScreen: CGRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32))
        timer?.invalidate()
        deadline = Date().addingTimeInterval(180)
        observedSettingsRunning = false
        // PermissionFlow owns the overlay. This bounded session closes its tracker after approval.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refresh()
                let settingsIsOpen = NSWorkspace.shared.runningApplications.contains {
                    $0.bundleIdentifier == "com.apple.systempreferences"
                }
                if settingsIsOpen { self.observedSettingsRunning = true }
                if (!settingsIsOpen && self.observedSettingsRunning) || Date() >= (self.deadline ?? .distantPast) {
                    self.close()
                }
            }
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        deadline = nil
        controller.closePanel()
    }
}

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore
    private let guide = AccessibilityGuide()
    private var finishedSession = false
    var onFinish: (() -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 558),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = L("Welcome to Puv")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func present() {
        finishedSession = false
        guide.refresh()
        window?.contentViewController = NSHostingController(rootView: OnboardingView(
            guide: guide, hotKey: settings.hotKey, onFinish: { [weak self] in self?.finish() }
        ))
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        guard !finishedSession else { return }
        finishedSession = true
        settings.hasCompletedOnboarding = true
        guide.close()
        close()
        // Releasing the artwork stops its Metal display link and permission observers.
        window?.contentViewController = nil
        onFinish?()
    }

    func windowWillClose(_ notification: Notification) { finish() }
    func stopPermissionGuidance() { guide.close() }
}

private struct OnboardingView: View {
    @ObservedObject var guide: AccessibilityGuide
    let hotKey: HotKey
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WelcomeArtwork().frame(height: 235).padding(.top, 12)
            Text("Puv").font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary)
            Text(L("Copy. Press. Keep.")).font(.system(size: 31, weight: .semibold)).padding(.top, 8)
            Text(L("Images and words, right where you need them."))
                .font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 8)
            HStack(spacing: 7) {
                ForEach(hotKey.displayComponents, id: \.self) { component in
                    Text(component).font(.system(size: 15, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
                }
            }.padding(.top, 20)
            Spacer(minLength: 14)
            Button(action: guide.authorize) {
                Label(L(guide.isGranted ? "Accessibility enabled" : "Enable global shortcut recording"),
                      systemImage: guide.isGranted ? "checkmark.circle.fill" : "hand.raised")
                    .foregroundStyle(guide.isGranted ? .green : .primary)
            }.buttonStyle(.link).disabled(guide.isGranted)
            Text(L("Optional Accessibility access. Pasting works without it."))
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 6)
            Button(L("Start using Puv"), action: onFinish)
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                .padding(.top, 20)
            Spacer(minLength: 24)
        }
        .frame(width: 520, height: 558)
        .background(Color(nsColor: .windowBackgroundColor))
        .transaction { $0.animation = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guide.refresh()
        }
    }
}
