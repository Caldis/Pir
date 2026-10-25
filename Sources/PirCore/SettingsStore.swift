import Foundation

public final class SettingsStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var hotKey: HotKey {
        get {
            guard let data = defaults.data(forKey: "hotKey"),
                  let value = try? JSONDecoder().decode(HotKey.self, from: data), value.isValid else {
                return .default
            }
            return value
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "hotKey") }
    }

    public var hideStatusItem: Bool {
        get { defaults.bool(forKey: "hideStatusItem") }
        set { defaults.set(newValue, forKey: "hideStatusItem") }
    }

    public var hotKeyEnabled: Bool {
        get { defaults.object(forKey: "hotKeyEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "hotKeyEnabled") }
    }

    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }
}
