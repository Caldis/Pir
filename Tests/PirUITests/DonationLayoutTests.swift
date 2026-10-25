import AppKit
import XCTest
@testable import Pir

@MainActor
final class DonationLayoutTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testDonationPreservesMosHeaderPaymentColumnAndFullHeightPhoto() throws {
        let controller = DonationController()
        controller.loadViewIfNeeded()
        XCTAssertEqual(controller.view.fittingSize, controller.preferredContentSize)
        let window = NSWindow(contentViewController: controller)
        defer { window.close() }
        controller.view.layoutSubtreeIfNeeded()
        let root = controller.view
        XCTAssertFalse(root is NSVisualEffectView)
        XCTAssertEqual(controller.preferredContentSize, NSSize(width: 705, height: 691))
        XCTAssertEqual(root.bounds.size, controller.preferredContentSize)
        let payments = try XCTUnwrap(root.subviews.first { $0.identifier?.rawValue == "donation-payments" })
        let photo = try XCTUnwrap(root.subviews.first { $0.identifier?.rawValue == "donation-photo" } as? NSImageView)
        let header = try XCTUnwrap(root.subviews.first { $0.identifier?.rawValue == "donation-cat-link" } as? NSButton)
        XCTAssertEqual(header.bezelStyle, .regularSquare)
        let headerAlignment = header.alignmentRect(forFrame: header.frame)
        XCTAssertEqual(root.bounds.maxY - headerAlignment.maxY, 20, accuracy: 0.5)
        XCTAssertEqual(headerAlignment.height, 32, accuracy: 0.5)
        XCTAssertEqual(payments.frame.width, 240, accuracy: 0.5)
        XCTAssertEqual(photo.frame, NSRect(x: 241, y: 0, width: 464, height: 618))
        XCTAssertNotNil(photo.image)
        XCTAssertEqual(payments.subviews.count, 8)
        let logosAndCodes = payments.subviews.compactMap { $0 as? NSImageView }
        XCTAssertEqual(logosAndCodes.count, 6)
        XCTAssertTrue(logosAndCodes.allSatisfy { $0.image != nil })
        XCTAssertTrue(payments.subviews.allSatisfy { payments.bounds.contains($0.frame) })
        XCTAssertEqual(payments.subviews.compactMap { $0 as? NSButton }.map(\.tag), [1, 2])
    }

    func testPaymentAssetsRespondToLightAndDarkAppearances() throws {
        let controller = DonationController()
        controller.loadViewIfNeeded()
        let payments = try XCTUnwrap(controller.view.subviews.first { $0.identifier?.rawValue == "donation-payments" })
        let images = payments.subviews.compactMap { $0 as? NSImageView }
        for image in images.prefix(5) {
            image.appearance = NSAppearance(named: .aqua)
            image.viewDidChangeEffectiveAppearance()
            let light = try XCTUnwrap(image.image)
            image.appearance = NSAppearance(named: .darkAqua)
            image.viewDidChangeEffectiveAppearance()
            let dark = try XCTUnwrap(image.image)
            XCTAssertFalse(light === dark)
        }
    }
}
