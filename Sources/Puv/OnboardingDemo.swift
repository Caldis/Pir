import AppKit
import SwiftUI
import Vortex

final class OnboardingDemoController {
    private let pins: PinManager
    private let reduceMotion: () -> Bool
    private let celebrationDuration: TimeInterval
    private var demoPinID: UUID?
    private var cleanup: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?
    private(set) var celebrationPanel: NSPanel?

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
        stopCelebration()
        guard !reduceMotion() else { return }
        let panel = CelebrationPanel(screen: screen)
        celebrationPanel = panel
        panel.orderFrontRegardless()
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

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentViewController = NSHostingController(rootView: ScreenFireworks())
    }
}

private struct ScreenFireworks: View {
    private let systems: [VortexSystem] = [
        makeSystem(position: [0.07, 0.82], angle: 20),
        makeSystem(position: [0.93, 0.82], angle: -20),
        makeSystem(position: [0.12, 0.12], angle: 160),
        makeSystem(position: [0.88, 0.12], angle: 200)
    ]

    var body: some View {
        ZStack {
            ForEach(systems) { system in
                VortexView(system, targetFrameRate: 60) {
                    Circle().fill(.white).frame(width: 28, height: 28)
                        .blendMode(.plusLighter).tag("circle")
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func makeSystem(position: SIMD2<Double>, angle: Double) -> VortexSystem {
        // Presets are shared instances; each celebration owns fresh simulation state.
        let system = VortexSystem.fireworks.makeUniqueCopy()
        system.position = position
        system.angle = .degrees(angle)
        system.angleRange = .degrees(16)
        system.birthRate = 8
        system.emissionLimit = 2
        system.lifespan = 0.45
        system.speed = 0.24
        system.speedVariation = 0.04
        for secondary in system.secondarySystems where secondary.spawnOccasion == .onDeath {
            secondary.birthRate = 6000
            secondary.emissionLimit = 130
            secondary.lifespan = 1.4
            secondary.speed = 0.18
            secondary.speedVariation = 0.14
            secondary.acceleration = [0, 0.2]
            secondary.dampingFactor = 2
        }
        return system
    }
}
