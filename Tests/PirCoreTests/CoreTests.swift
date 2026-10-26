import AppKit
import XCTest
@testable import PirCore

final class CoreTests: XCTestCase {
    private func isolatedPasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("PirTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    func testCopiedFilesTakePriorityOverFinderTextAndRoundTripLayout() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let files = [URL(fileURLWithPath: "/tmp/Pir File A.txt"), URL(fileURLWithPath: "/tmp/Pir File B.png")]
        pasteboard.writeObjects(files.map { $0 as NSURL })
        pasteboard.setString("Pir File A.txt\nPir File B.png", forType: .string)
        guard case .files(var content) = try ClipboardReader.read(from: pasteboard) else { return XCTFail("Expected file references") }
        XCTAssertEqual(content.urls, files)
        content.layout = .list
        let restored = try JSONDecoder().decode(FilePinContent.self, from: JSONEncoder().encode(content))
        XCTAssertEqual(restored, content)
    }

    func testClipboardPreservesWhitespaceAndUnicode() throws {
        let pasteboard = isolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let original = "  title\n\tlet value = 1\n\n中文 😀\n"
        pasteboard.declareTypes([.string], owner: nil)
        XCTAssertTrue(pasteboard.setString(original, forType: .string))
        XCTAssertTrue(pasteboard.types?.contains(.string) == true)
        XCTAssertFalse(pasteboard.types?.contains(.png) == true)
        XCTAssertFalse(pasteboard.types?.contains(.tiff) == true)
        XCTAssertEqual(pasteboard.string(forType: .string), original)
        guard case .text(let value) = try ClipboardReader.read(from: pasteboard) else {
            return XCTFail("Expected plain text")
        }
        XCTAssertEqual(value, original)
    }

    func testClipboardPrefersImageOverText() throws {
        let pasteboard = isolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 3,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        pasteboard.declareTypes([.png, .string], owner: nil)
        XCTAssertTrue(pasteboard.setData(bitmap.representation(using: .png, properties: [:])!, forType: .png))
        XCTAssertTrue(pasteboard.setString("Image title", forType: .string))
        guard case .image(let image) = try ClipboardReader.read(from: pasteboard) else {
            return XCTFail("Expected image when clipboard has both representations")
        }
        XCTAssertEqual(image.size.width, 2)
        XCTAssertEqual(image.size.height, 3)
    }

    func testInvalidImageFallsBackToText() throws {
        let pasteboard = isolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(Data([0, 1, 2]), forType: .png)
        pasteboard.setString("text fallback", forType: .string)
        guard case .text(let value) = try ClipboardReader.read(from: pasteboard) else {
            return XCTFail("Expected available text after invalid image representation")
        }
        XCTAssertEqual(value, "text fallback")
    }

    func testJPEGRepresentationIsRecognizedAsImage() throws {
        let pasteboard = isolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3,
                                      bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        pasteboard.setData(bitmap.representation(using: .jpeg, properties: [:])!,
                           forType: NSPasteboard.PasteboardType("public.jpeg"))
        guard case .image(let image) = try ClipboardReader.read(from: pasteboard) else {
            return XCTFail("Expected a JPEG image")
        }
        XCTAssertEqual(image.size, NSSize(width: 4, height: 3))
    }

    func testUnsupportedClipboardReportsError() {
        let pasteboard = isolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        XCTAssertThrowsError(try ClipboardReader.read(from: pasteboard))
    }

    func testLargeImageIsDownsampledBeforeRetention() throws {
        let pasteboard = isolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8192, pixelsHigh: 4,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        pasteboard.setData(bitmap.representation(using: .png, properties: [:])!, forType: .png)
        guard case .image(let image) = try ClipboardReader.read(from: pasteboard) else {
            return XCTFail("Expected a downsampled image")
        }
        XCTAssertEqual(image.representations.first?.pixelsWide, ClipboardReader.maximumImageDimension)
        XCTAssertEqual(image.representations.first?.pixelsHigh, 2)
        XCTAssertEqual(image.size.width, 8192)
        XCTAssertEqual(image.size.height, 4)
    }

    func testRetinaTIFFPreservesLogicalPointSize() throws {
        let pasteboard = isolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: 400, height: 300)
        let tiff = try XCTUnwrap(bitmap.tiffRepresentation)
        pasteboard.declareTypes([.tiff], owner: nil)
        XCTAssertTrue(pasteboard.setData(tiff, forType: .tiff))
        XCTAssertEqual(pasteboard.data(forType: .tiff), tiff)
        guard case .image(let image) = try ClipboardReader.read(from: pasteboard) else {
            return XCTFail("Expected Retina TIFF")
        }
        XCTAssertEqual(image.size.width, 400, accuracy: 1)
        XCTAssertEqual(image.size.height, 300, accuracy: 1)
        XCTAssertEqual(image.representations.first?.pixelsWide, 800)
    }

    func testOversizedTextReportsSizeError() {
        let pasteboard = isolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString(String(repeating: "A", count: ClipboardReader.maximumTextBytes + 1), forType: .string)
        XCTAssertThrowsError(try ClipboardReader.read(from: pasteboard)) { error in
            guard case ClipboardError.tooLarge = error else { return XCTFail("Expected size error") }
        }
    }

    func testRTFOnlyClipboardRetainsTextLayout() throws {
        let pasteboard = isolatedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let original = "  Heading\n\tIndented\n"
        let attributed = NSAttributedString(string: original)
        let rtf = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        pasteboard.declareTypes([.rtf], owner: nil)
        XCTAssertTrue(pasteboard.setData(rtf, forType: .rtf))
        XCTAssertEqual(pasteboard.data(forType: .rtf), rtf)
        guard case .text(let value) = try ClipboardReader.read(from: pasteboard) else {
            return XCTFail("Expected plain text from RTF")
        }
        XCTAssertEqual(value, original)
    }

    func testHotKeyRequiresModifierExceptFunctionKeys() {
        XCTAssertFalse(HotKey(keyCode: 9, modifiers: []).isValid)
        XCTAssertFalse(HotKey(keyCode: 55, modifiers: [.command]).isValid)
        XCTAssertFalse(HotKey(keyCode: 53, modifiers: [.command]).isValid)
        XCTAssertTrue(HotKey(keyCode: 122, modifiers: []).isValid)
        XCTAssertTrue(HotKey.default.isValid)
    }

    func testNewUserAndResetToDefaultUseShiftCommandVWhileSavedBindingsRemain() throws {
        let name = "PirTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        let expected = HotKey(keyCode: 9, modifiers: [.shift, .command])
        XCTAssertEqual(settings.hotKey, expected)
        let saved = HotKey(keyCode: 9, modifiers: [.command, .option])
        settings.hotKey = saved
        XCTAssertEqual(SettingsStore(defaults: defaults).hotKey, saved)
        settings.hotKey = .default
        XCTAssertEqual(SettingsStore(defaults: defaults).hotKey, expected)
    }

    func testFailedReplacementKeepsWorkingRegistration() throws {
        let backend = FakeHotKeyBackend()
        let binding = HotKeyBinding(backend: backend)
        try binding.replace(with: .default)
        backend.failure = true
        XCTAssertThrowsError(try binding.replace(with: HotKey(keyCode: 35, modifiers: [.command, .option])))
        XCTAssertEqual(binding.current, .default)
        XCTAssertEqual(backend.active, [1])
    }

    func testSuccessfulReplacementReleasesOldRegistration() throws {
        let backend = FakeHotKeyBackend()
        let binding = HotKeyBinding(backend: backend)
        try binding.replace(with: .default)
        try binding.replace(with: HotKey(keyCode: 35, modifiers: [.command, .option]))
        XCTAssertEqual(backend.active, [2])
        binding.clear()
        XCTAssertTrue(backend.active.isEmpty)
    }

    func testReapplyingIdenticalHotKeyAvoidsDuplicateRegistration() throws {
        let backend = FakeHotKeyBackend()
        let binding = HotKeyBinding(backend: backend)
        try binding.replace(with: .default)
        try binding.replace(with: .default)
        XCTAssertEqual(backend.active, [1])
    }

    func testInvalidReplacementKeepsExistingShortcut() throws {
        let backend = FakeHotKeyBackend()
        let binding = HotKeyBinding(backend: backend)
        try binding.replace(with: .default)
        XCTAssertThrowsError(try binding.replace(with: HotKey(keyCode: 9, modifiers: [])))
        XCTAssertEqual(binding.current, .default)
        XCTAssertEqual(backend.active, [1])
    }

    func testImageInitialSizeRespectsScreenAndAspectRatio() {
        let size = PinGeometry.initialSize(content: CGSize(width: 4000, height: 2000),
                                           available: CGSize(width: 1000, height: 700))
        XCTAssertLessThanOrEqual(size.width, 800)
        XCTAssertEqual(size.width / size.height, 2, accuracy: 0.001)
    }

    func testMinimumResizeAnchorsOppositeCorner() {
        let frame = CGRect(x: 40, y: 50, width: 300, height: 200)
        let resized = PinGeometry.resize(frame: frame, delta: CGPoint(x: 1000, y: 1000), edges: [.left, .bottom])
        XCTAssertEqual(resized.width, PinGeometry.minimumSize.width)
        XCTAssertEqual(resized.height, PinGeometry.minimumSize.height)
        XCTAssertEqual(resized.maxX, frame.maxX)
        XCTAssertEqual(resized.maxY, frame.maxY)
    }

    func testMalformedStoredShortcutUsesDefault() {
        let name = "PirTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("broken".utf8), forKey: "hotKey")
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.hotKey, .default)
        settings.hotKey = HotKey(keyCode: 35, modifiers: [.command])
        XCTAssertEqual(SettingsStore(defaults: defaults).hotKey, settings.hotKey)
    }

    func testOnboardingCompletionPersistsIndependentlyOfShortcutSettings() {
        let name = "PirTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.hasCompletedOnboarding)
        settings.hasCompletedOnboarding = true
        XCTAssertTrue(SettingsStore(defaults: defaults).hasCompletedOnboarding)
        XCTAssertEqual(settings.hotKey, .default)
        XCTAssertFalse(settings.hideStatusItem)
    }

    func testSessionRecordFromBeforeVisibilitySettingDefaultsToVisible() throws {
        let display = PinDisplay(id: "display", visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let record = PinRecord(id: UUID(), kind: .text,
                               anchor: PinAnchor(frame: CGRect(x: 10, y: 10, width: 300, height: 200), display: display),
                               imagePointSize: nil, isHidden: true)
        let encoded = try JSONEncoder().encode(record)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        fields.removeValue(forKey: "isHidden")
        let previousFormat = try JSONSerialization.data(withJSONObject: fields)
        let decoded = try JSONDecoder().decode(PinRecord.self, from: previousFormat)
        XCTAssertFalse(decoded.isHidden)
        XCTAssertEqual(decoded.id, record.id)
    }
}

private final class FakeHotKeyBackend: HotKeyBackend {
    var active: Set<Int> = []
    var failure = false
    private var counter = 0
    func register(_ hotKey: HotKey) throws -> Int {
        if failure { throw NSError(domain: "TestConflict", code: 1) }
        counter += 1
        active.insert(counter)
        return counter
    }
    func unregister(_ token: Int) { active.remove(token) }
}
