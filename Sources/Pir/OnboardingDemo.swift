import AppKit
import SwiftUI
import Vortex

final class OnboardingDemoController {
    private let pins: PinManager
    private let reduceMotion: () -> Bool
    private let celebrationDuration: TimeInterval
    private var demoPinID: UUID?
    private var cleanup: DispatchWorkItem?
    private var celebration: ScreenFireworksState?
    private var celebrationScreenFrame: NSRect?
    private var screenObserver: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?
    private(set) var celebrationPanel: NSPanel?
    var activeCelebrationBurstCount: Int { celebration?.bursts.count ?? 0 }

    init(pins: PinManager,
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         celebrationDuration: TimeInterval = 3.2) {
        self.pins = pins
        self.reduceMotion = reduceMotion
        self.celebrationDuration = celebrationDuration
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.stopCelebration() }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            if self?.reduceMotion() == true { self?.stopCelebration() }
        }
    }

    func showLogo(on preferredScreen: NSScreen?) throws {
        guard let screen = preferredScreen ?? NSScreen.main else { return }
        if demoPinID.map({ pins.reveal($0) }) != true {
            let image = NSApp.applicationIconImage.copy() as! NSImage
            image.size = NSSize(width: 192, height: 192)
            demoPinID = try pins.show(.image(image), on: screen)
        }
        guard demoPinID != nil else { return }
        guard !reduceMotion() else { stopCelebration(); return }
        if celebrationScreenFrame != screen.frame { stopCelebration() }
        if celebrationPanel == nil {
            let state = ScreenFireworksState()
            let panel = CelebrationPanel(screen: screen, state: state)
            celebration = state
            celebrationPanel = panel
            celebrationScreenFrame = screen.frame
            panel.orderFrontRegardless()
        }
        celebration?.addBurst()
        cleanup?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stopCelebration() }
        cleanup = work
        DispatchQueue.main.asyncAfter(deadline: .now() + celebrationDuration, execute: work)
    }

    func stopCelebration() {
        cleanup?.cancel()
        cleanup = nil
        // Removing the hosting controller ends Vortex's TimelineView rendering immediately.
        celebrationPanel?.contentViewController = nil
        celebrationPanel?.close()
        celebrationPanel = nil
        celebration = nil
        celebrationScreenFrame = nil
    }

    deinit {
        stopCelebration()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }
}

private final class CelebrationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen, state: ScreenFireworksState) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentViewController = NSHostingController(rootView: ScreenFireworks(state: state)
            .frame(width: screen.frame.width, height: screen.frame.height))
    }
}

private final class ScreenFireworksState: ObservableObject {
    @Published private(set) var bursts: [FireworkBurst] = []

    func addBurst() {
        bursts.append(FireworkBurst())
        // Keep rapid presses responsive while bounding live particle simulations.
        if bursts.count > OnboardingFireworks.maximumBurstCount {
            bursts.removeFirst(bursts.count - OnboardingFireworks.maximumBurstCount)
        }
    }
}

private struct ScreenFireworks: View {
    @ObservedObject var state: ScreenFireworksState

    var body: some View {
        ZStack {
            ForEach(state.bursts) { burst in
                ForEach(burst.systems) { system in
                    VortexView(system, targetFrameRate: 60) {
                        Circle().fill(.white)
                            .frame(width: OnboardingFireworks.particleDiameter, height: OnboardingFireworks.particleDiameter)
                            .blendMode(.plusLighter).tag("circle")
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum OnboardingFireworks {
    static let particleDiameter: CGFloat = 84
    static let maximumBurstCount = 4
}

struct FireworkBurst: Identifiable {
    let id = UUID()
    let systems: [VortexSystem]

    init(randomValue: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) {
        let regions: [(ClosedRange<Double>, ClosedRange<Double>)] = [
            (0.16...0.44, 0.56...0.84), (0.56...0.84, 0.56...0.84),
            (0.16...0.44, 0.16...0.44), (0.56...0.84, 0.16...0.44)
        ]
        systems = regions.map { x, y in
            let position = SIMD2(randomValue(x), randomValue(y))
            let angle = atan2(0.5 - position.x, position.y - 0.5) * 180 / .pi
            return Self.makeSystem(position: position, angle: angle)
        }
    }

    private static func makeSystem(position: SIMD2<Double>, angle: Double) -> VortexSystem {
        // Presets are shared instances; each celebration owns fresh simulation state.
        let system = VortexSystem.fireworks.makeUniqueCopy()
        system.position = position
        system.angle = .degrees(angle)
        system.angleRange = .degrees(16)
        system.birthRate = 60
        system.emissionLimit = 1
        system.lifespan = 0.04
        system.speed = 0.24
        system.speedVariation = 0.04
        for secondary in system.secondarySystems where secondary.spawnOccasion == .onDeath {
            secondary.birthRate = 6000
            secondary.emissionLimit = 130
            secondary.lifespan = 1.4
            secondary.speed = 0.54
            secondary.speedVariation = 0.42
            secondary.acceleration = [0, 0.2]
            secondary.dampingFactor = 2
        }
        return system
    }
}
