import Foundation
import XCTest
@testable import Puv

final class UpdateTests: XCTestCase {
    func testUpdatePreferencesPersistAndBetaOptInRetainsStableChannel() throws {
        let domain = "Puv.UpdateTests.\(UUID().uuidString)"
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

    func testUpdateDownloadsAreRestrictedToPuvReleaseAssets() {
        XCTAssertTrue(UpdateDistribution.acceptsDownloadURL(URL(string: "https://github.com/Caldis/Puv/releases/download/0.2.0/Puv.Versions.0.2.0-20261025.1.zip")))
        for location in ["http://github.com/Caldis/Puv/releases/download/0.2.0/Puv.zip",
                         "https://github.com.evil.example/Caldis/Puv/releases/download/0.2.0/Puv.zip",
                         "https://github.com/Caldis/Mos/releases/download/0.2.0/Puv.zip",
                         "https://github.com/Caldis/Puv/releases/latest",
                         "https://github.com/Caldis/Puv/releases/download/0.2.0",
                         "https://github.com:444/Caldis/Puv/releases/download/0.2.0/Puv.zip",
                         "https://guest@github.com/Caldis/Puv/releases/download/0.2.0/Puv.zip"] {
            XCTAssertFalse(UpdateDistribution.acceptsDownloadURL(URL(string: location)), location)
        }
    }
}
