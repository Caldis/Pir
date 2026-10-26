import AppKit
import XCTest
import PirCore
@testable import Pir

@MainActor
final class OnboardingTests: XCTestCase {
    func testCompletedReleaseLaunchStaysQuietWhileDebugAndHiddenIconLaunchExposePreferences() {
        XCTAssertEqual(AppLaunchPolicy.presentation(hasCompletedOnboarding: true, isLoginLaunch: false,
            isDebugBuild: false, statusItemHidden: false), .none)
        XCTAssertEqual(AppLaunchPolicy.presentation(hasCompletedOnboarding: true, isLoginLaunch: false,
            isDebugBuild: true, statusItemHidden: false), .preferences)
        XCTAssertEqual(AppLaunchPolicy.presentation(hasCompletedOnboarding: true, isLoginLaunch: false,
            isDebugBuild: false, statusItemHidden: true), .preferences)
        for completed in [false, true] {
            XCTAssertEqual(AppLaunchPolicy.presentation(hasCompletedOnboarding: completed, isLoginLaunch: true,
                isDebugBuild: true, statusItemHidden: true), .none)
        }
        XCTAssertEqual(AppLaunchPolicy.presentation(hasCompletedOnboarding: false, isLoginLaunch: false,
            isDebugBuild: false, statusItemHidden: false), .onboarding)
    }

    func testWelcomeFrameCentersInAvailableScreenAndRecentersOnAnotherScreen() throws {
        _ = NSApplication.shared
        let domain = "Pir.OnboardingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = SettingsStore(defaults: defaults)
        let model = PreferencesModel(settings: settings, pins: PinManager())
        let controller = OnboardingWindowController(settings: settings, model: model)
        let window = try XCTUnwrap(controller.window)
        for screen in [NSRect(x: 0, y: 70, width: 1440, height: 806),
                       NSRect(x: -1920, y: -300, width: 1920, height: 1055)] {
            controller.center(on: screen)
            XCTAssertEqual(window.frame.midX, screen.midX, accuracy: 0.5)
            XCTAssertEqual(window.frame.midY, screen.midY, accuracy: 0.5)
        }
    }

    func testFireworksSampleNewPositionsAndUseLargerParticlesAndSpread() throws {
        let first = FireworkBurst(randomValue: { $0.lowerBound })
        let second = FireworkBurst(randomValue: { $0.upperBound })
        XCTAssertEqual(first.systems.count, 4)
        XCTAssertEqual(second.systems.count, 4)
        XCTAssertGreaterThanOrEqual(OnboardingFireworks.particleDiameter, 84)
        for (a, b) in zip(first.systems, second.systems) {
            XCTAssertNotEqual(a.position, b.position)
            for system in [a, b] {
                XCTAssertTrue((0...1).contains(system.position.x))
                XCTAssertTrue((0...1).contains(system.position.y))
                let explosion = try XCTUnwrap(system.secondarySystems.first { $0.spawnOccasion == .onDeath })
                XCTAssertGreaterThanOrEqual(explosion.speed, 0.54)
                XCTAssertEqual(explosion.emissionLimit, 130)
            }
        }
    }

    func testShortcutOutlineFitsKeycapsWithEqualPaddingAndAdaptsToCombination() throws {
        _ = NSApplication.shared
        let domain = "Pir.OnboardingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let model = PreferencesModel(settings: SettingsStore(defaults: defaults), pins: PinManager())
        let button = RecorderButton(model: model, style: .onboarding)
        let preview = try XCTUnwrap(button.subviews.compactMap { $0 as? KeyPreview }.first)
        let small = HotKey(keyCode: 9, modifiers: [.command])
        let large = HotKey(keyCode: 49, modifiers: [.command, .shift, .control, .option])
        var widths: [CGFloat] = []
        for key in [small, large] {
            button.update(key, enabled: true)
            button.setFrameSize(button.intrinsicContentSize)
            button.layoutSubtreeIfNeeded()
            let rect = preview.convert(preview.bounds, to: button)
            XCTAssertEqual(rect.minX, 8, accuracy: 0.5)
            XCTAssertEqual(button.bounds.maxX - rect.maxX, 8, accuracy: 0.5)
            XCTAssertEqual(rect.minY, 8, accuracy: 0.5)
            XCTAssertEqual(button.bounds.maxY - rect.maxY, 8, accuracy: 0.5)
            widths.append(button.frame.width)
        }
        XCTAssertGreaterThan(widths[1], widths[0])
    }

    func testRapidShortcutPressesKeepPanelAndAddCelebrations() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let pins = PinManager(store: PinSessionStore(root: root))
        let demo = OnboardingDemoController(pins: pins, reduceMotion: { false })
        defer { demo.stopCelebration(); pins.closeAll(); try? FileManager.default.removeItem(at: root) }
        try demo.showLogo(on: NSScreen.main)
        let panel = try XCTUnwrap(demo.celebrationPanel)
        for _ in 0..<12 { try demo.showLogo(on: NSScreen.main) }
        XCTAssertTrue(demo.celebrationPanel === panel)
        XCTAssertEqual(demo.activeCelebrationBurstCount, 4)
        XCTAssertEqual(pins.summaries.count, 1)
    }

    func testWelcomeShortcutRepeatsAndYieldsDuringRecording() throws {
        _ = NSApplication.shared
        let domain = "Pir.OnboardingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = SettingsStore(defaults: defaults)
        let model = PreferencesModel(settings: settings, pins: PinManager())
        let controller = OnboardingWindowController(settings: settings, model: model)
        var presses = 0
        controller.onTryShortcut = { _ in presses += 1; return true }
        controller.present()
        defer { controller.close() }
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: model.hotKey.modifiers, timestamp: 0, windowNumber: try XCTUnwrap(controller.window).windowNumber,
            context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: model.hotKey.keyCode))
        XCTAssertNil(controller.handleShortcutEvent(event))
        XCTAssertNil(controller.handleShortcutEvent(event))
        XCTAssertEqual(presses, 2)
        model.isRecording = true
        XCTAssertNotNil(controller.handleShortcutEvent(event))
        XCTAssertEqual(presses, 2)
    }

    func testDemoReusesHiddenPinAndRecreatesDeletedPin() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PinSessionStore(root: root)
        let pins = PinManager(store: store)
        let demo = OnboardingDemoController(pins: pins, reduceMotion: { true })
        defer { demo.stopCelebration(); pins.closeAll(); try? FileManager.default.removeItem(at: root) }

        try demo.showLogo(on: NSScreen.main)
        let first = try XCTUnwrap(pins.summaries.first)
        XCTAssertEqual(first.kind, .image)
        pins.setHidden(true, for: first.id)
        try demo.showLogo(on: NSScreen.main)
        XCTAssertEqual(pins.summaries.count, 1)
        XCTAssertEqual(pins.summaries.first?.id, first.id)
        XCTAssertFalse(try XCTUnwrap(pins.summaries.first).isHidden)
        XCTAssertNil(demo.celebrationPanel)

        pins.delete(first.id)
        try demo.showLogo(on: NSScreen.main)
        XCTAssertEqual(pins.summaries.count, 1)
        XCTAssertNotEqual(pins.summaries.first?.id, first.id)
        pins.flushSession()
        let saved = try XCTUnwrap(store.load().first)
        XCTAssertEqual(saved.record.imagePointSize, NSSize(width: 192, height: 192))
        XCTAssertNotNil(NSImage(data: saved.data))
    }

    func testCelebrationIsClickThroughAndReleasesOnDeadline() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let pins = PinManager(store: PinSessionStore(root: root))
        let demo = OnboardingDemoController(pins: pins, reduceMotion: { false }, celebrationDuration: 0.05)
        defer { demo.stopCelebration(); pins.closeAll(); try? FileManager.default.removeItem(at: root) }
        try demo.showLogo(on: NSScreen.main)
        let panel = try XCTUnwrap(demo.celebrationPanel)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertFalse(panel.hasShadow)
        let ended = expectation(description: "Celebration resources released")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            XCTAssertNil(demo.celebrationPanel)
            XCTAssertNil(panel.contentViewController)
            XCTAssertFalse(panel.isVisible)
            ended.fulfill()
        }
        wait(for: [ended], timeout: 2)
    }

    func testScreenChangeStopsCelebrationWithoutDeletingPin() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let pins = PinManager(store: PinSessionStore(root: root))
        let demo = OnboardingDemoController(pins: pins, reduceMotion: { false })
        defer { demo.stopCelebration(); pins.closeAll(); try? FileManager.default.removeItem(at: root) }
        try demo.showLogo(on: NSScreen.main)
        XCTAssertNotNil(demo.celebrationPanel)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        XCTAssertNil(demo.celebrationPanel)
        XCTAssertEqual(pins.summaries.count, 1)
    }
}
