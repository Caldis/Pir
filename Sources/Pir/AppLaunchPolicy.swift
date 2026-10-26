enum AppLaunchPolicy {
    enum Presentation: Equatable {
        case none
        case onboarding
        case preferences
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static func presentation(hasCompletedOnboarding: Bool, isLoginLaunch: Bool,
                             isDebugBuild: Bool, statusItemHidden: Bool) -> Presentation {
        guard !isLoginLaunch else { return .none }
        guard hasCompletedOnboarding else { return .onboarding }
        return isDebugBuild || statusItemHidden ? .preferences : .none
    }
}
