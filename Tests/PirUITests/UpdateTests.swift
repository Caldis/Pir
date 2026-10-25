import Foundation
import XCTest
@testable import Pir

final class UpdateTests: XCTestCase {
    func testUpdatePreferencesPersistAndBetaOptInRetainsStableChannel() throws {
        let domain = "Pir.UpdateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let first = UpdatePreferences(defaults: defaults)
        XCTAssertFalse(first.checkOnAppStart)
        XCTAssertTrue(first.allowedChannels.isEmpty)
        first.checkOnAppStart = true
        first.includingBetaVersion = true
        let restored = UpdatePreferences(defaults: defaults)
        XCTAssertTrue(restored.checkOnAppStart)
        XCTAssertEqual(restored.allowedChannels, ["beta"])
        restored.includingBetaVersion = false
        XCTAssertTrue(restored.allowedChannels.isEmpty)
        XCTAssertFalse(UpdatePreferences(defaults: defaults).includingBetaVersion)
    }

    func testUpdateDownloadsAreRestrictedToPirReleaseAssets() {
        XCTAssertTrue(UpdateDistribution.acceptsDownloadURL(URL(string: "https://github.com/Caldis/Pir/releases/download/0.2.0/Pir.Versions.0.2.0-20261025.1.zip")))
        for location in ["http://github.com/Caldis/Pir/releases/download/0.2.0/Pir.zip",
                         "https://github.com.evil.example/Caldis/Pir/releases/download/0.2.0/Pir.zip",
                         "https://github.com/Caldis/Mos/releases/download/0.2.0/Pir.zip",
                         "https://github.com/Caldis/Pir/releases/latest",
                         "https://github.com/Caldis/Pir/releases/download/0.2.0",
                         "https://github.com:444/Caldis/Pir/releases/download/0.2.0/Pir.zip",
                         "https://guest@github.com/Caldis/Pir/releases/download/0.2.0/Pir.zip"] {
            XCTAssertFalse(UpdateDistribution.acceptsDownloadURL(URL(string: location)), location)
        }
    }
}
