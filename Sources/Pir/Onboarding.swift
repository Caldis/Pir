import AppKit
import SwiftUI
import PirCore

final class OnboardingExperience: ObservableObject {
    @Published var hasPinnedLogo = false
}

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore
    private let model: PreferencesModel
    private let experience = OnboardingExperience()
    private var finishedSession = false
    private var shortcutMonitor: Any?
    var onFinish: (() -> Void)?
    var onTryShortcut: ((NSScreen?) -> Bool)?

    init(settings: SettingsStore, model: PreferencesModel) {
        self.settings = settings
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 540),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = L("Welcome to Pir")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func present() {
        finishedSession = false
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleShortcutEvent(event)
        }
        experience.hasPinnedLogo = false
        window?.contentViewController = NSHostingController(rootView: OnboardingView(
            model: model, experience: experience,
            onTryShortcut: { [weak self] in self?.tryShortcut() },
            onFinish: { [weak self] in self?.finish() }
        ))
        if let screen = NSScreen.main ?? window?.screen { center(on: screen.visibleFrame) }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func center(on visibleFrame: NSRect) {
        guard let window else { return }
        window.setFrameOrigin(NSPoint(x: visibleFrame.midX - window.frame.width / 2,
                                      y: visibleFrame.midY - window.frame.height / 2))
    }

    private func finish() {
        guard !finishedSession else { return }
        finishedSession = true
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        settings.hasCompletedOnboarding = true
        close()
        // Releasing the artwork stops its Metal display link.
        window?.contentViewController = nil
        onFinish?()
    }

    func windowWillClose(_ notification: Notification) { finish() }

    func handleShortcutEvent(_ event: NSEvent) -> NSEvent? {
        guard window?.isVisible == true, event.window === window, !model.isRecording,
              model.hotKeyEnabled, HotKey(keyCode: event.keyCode, modifiers: event.modifierFlags) == model.hotKey else { return event }
        // Registered Carbon events are consumed before this app-local fallback reaches AppKit.
        tryShortcut()
        return nil
    }

    deinit {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
    }

    func tryShortcut() {
        guard window?.isVisible == true else { return }
        if onTryShortcut?(window?.screen) == true { experience.hasPinnedLogo = true }
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var experience: OnboardingExperience
    let onTryShortcut: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WelcomeArtwork().frame(height: 235).padding(.top, 12)
            Text("Pir").font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary)
            Text(L("Copy. Press. Keep.")).font(.system(size: 31, weight: .semibold)).padding(.top, 8)
            Text(L("Images and words, right where you need them."))
                .font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 8)
            OnboardingShortcutControl(model: model, onRecorded: onTryShortcut)
                .fixedSize().padding(.top, 20)
            Text(L(experience.hasPinnedLogo ? "Pinned! Try dragging or resizing the logo." : "Click to change. Press the shortcut to try Pir."))
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 10)
            if let error = model.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).padding(.top, 6)
            }
            Spacer(minLength: 14)
            Button(action: onFinish) {
                Text(L("Start using Pir")).frame(minWidth: 168, minHeight: 28)
            }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                .padding(.top, 20)
            Spacer(minLength: 24)
        }
        .frame(width: 520, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .transaction { $0.animation = nil }
    }
}

private struct OnboardingShortcutControl: NSViewRepresentable {
    @ObservedObject var model: PreferencesModel
    let onRecorded: () -> Void

    func makeNSView(context: Context) -> RecorderButton {
        RecorderButton(model: model, style: .onboarding, onRecorded: onRecorded)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RecorderButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    func updateNSView(_ view: RecorderButton, context: Context) {
        view.update(model.hotKey, enabled: model.hotKeyEnabled)
    }
}
