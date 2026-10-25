import AppKit
import Combine
import Sparkle

enum UpdateDistribution {
    static let feedURL = "https://github.com/Caldis/Puv/releases/download/update-feed/appcast.xml"

    static func acceptsDownloadURL(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", url.host?.lowercased() == "github.com",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        let components = url.path.split(separator: "/")
        return components.count >= 6 && components[0].lowercased() == "caldis"
            && components[1].lowercased() == "puv" && components[2] == "releases" && components[3] == "download"
    }
}

@MainActor
final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateManager()
    let preferences: UpdatePreferences
    @Published private(set) var canCheckForUpdates = true
    private var started = false
    private var startupCheck: DispatchWorkItem?
    private var checkObservation: NSKeyValueObservation?
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false,
                                                              updaterDelegate: self, userDriverDelegate: nil)

    init(preferences: UpdatePreferences = UpdatePreferences()) {
        self.preferences = preferences
        super.init()
    }

    func scheduleCheckOnAppStartIfNeeded() {
        guard preferences.checkOnAppStart, startupCheck == nil else { return }
        let check = DispatchWorkItem { [weak self] in
            guard let self, self.preferences.checkOnAppStart, !self.started else { return }
            self.start()
            if self.started && self.controller.updater.canCheckForUpdates {
                self.controller.updater.checkForUpdatesInBackground()
            }
        }
        startupCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: check)
    }

    func checkForUpdates() {
        startupCheck?.cancel()
        start()
        guard started, controller.updater.canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    private func start() {
        // XCTest and bare SwiftPM executables have no application bundle to replace.
        guard !started, Bundle.main.bundleURL.pathExtension == "app" else { return }
        started = true
        checkObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let enabled = updater.canCheckForUpdates
            Task { @MainActor [weak self] in self?.canCheckForUpdates = enabled }
        }
        controller.startUpdater()
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> { preferences.allowedChannels }

    func feedURLString(for updater: SPUUpdater) -> String? { UpdateDistribution.feedURL }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem,
                 updateCheck: SPUUpdateCheck) throws {
        guard UpdateDistribution.acceptsDownloadURL(updateItem.fileURL) else {
            throw NSError(domain: "me.caldis.puv.updates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L("Update downloads must come from Puv’s GitHub Releases.")])
        }
    }
}
