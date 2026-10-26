import Foundation
import XCTest
@testable import PirCore

final class PinImageScalingTests: XCTestCase {
    func testImageModeRoundTripsAndLegacyMetadataDefaultsToCover() throws {
        let display = PinDisplay(id: "main", visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 900))
        let record = PinRecord(id: UUID(), kind: .image,
            anchor: PinAnchor(frame: CGRect(x: 100, y: 100, width: 300, height: 200), display: display),
            imagePointSize: CGSize(width: 600, height: 200), imageScaling: .fit)
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(PinRecord.self, from: data), record)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "imageScaling")
        let old = try JSONDecoder().decode(PinRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(old.imageScaling, .cover)
        XCTAssertEqual(old.anchor, record.anchor)
        legacy["imageScaling"] = "future-mode"
        let unknown = try JSONDecoder().decode(PinRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(unknown.imageScaling, .cover)
    }
}
