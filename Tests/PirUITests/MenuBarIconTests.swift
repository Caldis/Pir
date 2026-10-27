import AppKit
import XCTest
@testable import Pir

@MainActor
final class MenuBarIconTests: XCTestCase {
    func testMenuIconSelectsNativePixelsForStandardAndRetinaDisplays() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Pir.app/Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "Pir.MenuBarIconTests.\(UUID().uuidString)",
                                   "CFBundleName": "Pir", "CFBundlePackageType": "APPL"]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: resources.deletingLastPathComponent().appendingPathComponent("Info.plist"))
        let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets/brand")
        for name in ["MenuBarTemplate.png", "MenuBarTemplate@2x.png"] {
            try FileManager.default.copyItem(at: assets.appendingPathComponent(name),
                                            to: resources.appendingPathComponent(name))
        }
        let bundle = try XCTUnwrap(Bundle(url: resources.deletingLastPathComponent().deletingLastPathComponent()))
        let image = try XCTUnwrap(MenuBarIcon.image(in: bundle))
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(image.isTemplate)
        for scale in [1, 2] {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: 18 * scale, pixelsHigh: 18 * scale, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
            context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            let rep = try XCTUnwrap(image.bestRepresentation(for: NSRect(x: 0, y: 0, width: 18, height: 18),
                                                            context: context, hints: nil))
            XCTAssertEqual(rep.pixelsWide, 18 * scale)
            XCTAssertEqual(rep.pixelsHigh, 18 * scale)
            XCTAssertEqual(rep.size, NSSize(width: 18, height: 18))
        }
    }
}
