import Foundation
import XCTest
@testable import PuvCore

final class PinPersistenceTests: XCTestCase {
    func testDisplayRearrangementKeepsDisplayLocalPosition() {
        let original = PinDisplay(id: "external", visibleFrame: CGRect(x: -1920, y: 120, width: 1920, height: 1050))
        let anchor = PinAnchor(frame: CGRect(x: -1600, y: 300, width: 500, height: 400), display: original)
        let moved = PinDisplay(id: "external", visibleFrame: CGRect(x: 1440, y: -200, width: 1920, height: 1050))
        let placement = anchor.resolve(displays: [moved], fallbackDisplayID: moved.id)!
        XCTAssertEqual(placement.displayID, "external")
        XCTAssertEqual(placement.frame, CGRect(x: 1760, y: -20, width: 500, height: 400))
        XCTAssertFalse(placement.isFallback)
    }

    func testDisconnectedDisplayFallsBackWithoutChangingPreferredAnchor() {
        let external = PinDisplay(id: "external", visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let laptop = PinDisplay(id: "laptop", visibleFrame: CGRect(x: 0, y: 24, width: 1440, height: 850))
        let anchor = PinAnchor(frame: CGRect(x: -1000, y: 500, width: 600, height: 400), display: external)
        let fallback = anchor.resolve(displays: [laptop], fallbackDisplayID: laptop.id)!
        XCTAssertTrue(fallback.isFallback)
        XCTAssertTrue(laptop.visibleFrame.contains(fallback.frame))
        XCTAssertEqual(anchor.displayID, "external")
        let restored = anchor.resolve(displays: [laptop, external], fallbackDisplayID: laptop.id)!
        XCTAssertEqual(restored.frame.minX, -1000, accuracy: 0.001)
        XCTAssertEqual(restored.frame.minY, 500, accuracy: 0.001)
        XCTAssertEqual(restored.frame.size, CGSize(width: 600, height: 400))
        XCTAssertFalse(restored.isFallback)
    }

    func testResizingFallbackPreservesDisconnectedDisplayOwnership() {
        let external = PinDisplay(id: "external", visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let laptop = PinDisplay(id: "laptop", visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 850))
        let anchor = PinAnchor(frame: CGRect(x: -1500, y: 300, width: 400, height: 300), display: external)
        let fallback = anchor.resolve(displays: [laptop], fallbackDisplayID: laptop.id)!.frame
        let resized = CGRect(origin: fallback.origin, size: CGSize(width: 600, height: 500))
        let updated = anchor.updatedByUser(frame: resized, previousFrame: fallback, displays: [laptop])
        XCTAssertEqual(updated.displayID, "external")
        XCTAssertEqual(updated.size, resized.size)
        XCTAssertEqual(updated.horizontalFraction, anchor.horizontalFraction)
        let moved = updated.updatedByUser(frame: resized.offsetBy(dx: 60, dy: 40), previousFrame: resized, displays: [laptop])
        XCTAssertEqual(moved.displayID, "laptop")
    }

    func testSmallerScreenClampsSizeAndKeepsPinVisible() {
        let display = PinDisplay(id: "a", visibleFrame: CGRect(x: 0, y: 0, width: 3000, height: 2000))
        let anchor = PinAnchor(frame: CGRect(x: 500, y: 300, width: 2000, height: 1500), display: display)
        let small = PinDisplay(id: "a", visibleFrame: CGRect(x: -800, y: -600, width: 800, height: 550))
        let result = anchor.resolve(displays: [small], fallbackDisplayID: "a")!
        XCTAssertTrue(small.visibleFrame.contains(result.frame))
        XCTAssertEqual(result.frame.size, CGSize(width: 800, height: 550))
        XCTAssertEqual(anchor.size, CGSize(width: 2000, height: 1500))
    }

    func testDisplayChoiceUsesOverlapInsteadOfArrayOrder() {
        let left = PinDisplay(id: "left", visibleFrame: CGRect(x: -1000, y: 0, width: 1000, height: 800))
        let right = PinDisplay(id: "right", visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertEqual(PinDisplay.best(for: CGRect(x: -200, y: 100, width: 600, height: 300), among: [left, right])?.id, "right")
        XCTAssertEqual(PinDisplay.best(for: CGRect(x: -200, y: 100, width: 600, height: 300), among: [right, left])?.id, "right")
    }

    func testSessionRoundTripPreservesTextAndMetadataWithPrivatePermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PinSessionStore(root: root)
        let record = fixture()
        let text = "  heading\n\t中文 😀\n\n"
        try store.writeContent(Data(text.utf8), for: record.id)
        try store.save([record])
        let loaded = try PinSessionStore(root: root).load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].record, record)
        XCTAssertEqual(String(data: loaded[0].data, encoding: .utf8), text)
        let directoryMode = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as! NSNumber
        let fileMode = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(record.id.uuidString + ".json").path)[.posixPermissions] as! NSNumber
        XCTAssertEqual(directoryMode.intValue & 0o777, 0o700)
        XCTAssertEqual(fileMode.intValue & 0o777, 0o600)
    }

    func testCorruptAndMissingContentRecordsDoNotDiscardHealthyPins() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PinSessionStore(root: root)
        let healthy = fixture()
        let missing = fixture()
        try store.writeContent(Data("healthy".utf8), for: healthy.id)
        try store.save([healthy, missing])
        try Data("broken".utf8).write(to: root.appendingPathComponent(UUID().uuidString + ".json"))
        let loaded = try store.load()
        XCTAssertEqual(loaded.map(\.record.id), [healthy.id])
    }

    func testClosingPinDeletesContentAndMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PinSessionStore(root: root)
        let record = fixture()
        try store.writeContent(Data("text".utf8), for: record.id)
        try store.save([record])
        try store.save([])
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testMetadataChangesLeaveStoredContentUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PinSessionStore(root: root)
        var record = fixture()
        try store.writeContent(Data("unchanged".utf8), for: record.id)
        try store.save([record])
        let content = root.appendingPathComponent(record.id.uuidString + ".content")
        let before = try FileManager.default.attributesOfItem(atPath: content.path)[.modificationDate] as! Date
        record.anchor = PinAnchor(frame: CGRect(x: 200, y: 100, width: 400, height: 250), display: PinDisplay(id: "display", visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)))
        try store.save([record])
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: content.path)[.modificationDate] as! Date, before)
        XCTAssertEqual(try store.load()[0].record, record)
    }

    private func fixture() -> PinRecord {
        PinRecord(id: UUID(), kind: .text, anchor: PinAnchor(frame: CGRect(x: 50, y: 60, width: 400, height: 250), display: PinDisplay(id: "display", visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))), imagePointSize: nil, createdAt: Date(timeIntervalSince1970: 123456))
    }
}
