import Combine
import Foundation

final class UpdatePreferences: ObservableObject {
    private let defaults: UserDefaults

    @Published var checkOnAppStart: Bool {
        didSet { defaults.set(checkOnAppStart, forKey: "Updates.checkOnAppStart") }
    }
    @Published var includingBetaVersion: Bool {
        didSet { defaults.set(includingBetaVersion, forKey: "Updates.includingBetaVersion") }
    }

    var allowedChannels: Set<String> { includingBetaVersion ? ["beta"] : [] }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        checkOnAppStart = defaults.bool(forKey: "Updates.checkOnAppStart")
        includingBetaVersion = defaults.bool(forKey: "Updates.includingBetaVersion")
    }
}
