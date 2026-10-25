import XCTest
import AppKit
import MetalKit
@testable import Puv

final class LogoBirthTests: XCTestCase {
    @MainActor
    func testIconServicesImageCanBecomeMetalTexture() throws {
        _ = NSApplication.shared
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal device unavailable") }
        let icon = try XCTUnwrap(NSApp.applicationIconImage)
        var rect = CGRect(x: 0, y: 0, width: 512, height: 512)
        let image = try XCTUnwrap(icon.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        let texture = try LogoBirthView.makeLogoTexture(device: device, image: image)
        XCTAssertEqual(texture.pixelFormat, .rgba8Unorm)
        XCTAssertEqual(texture.width, 512)
    }

    func testMetalIntroRendersAndSettlesToStaticLogo() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal device unavailable") }
        let library = try LogoBirthView.makeShaderLibrary(device: device)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "logoVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "logoFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let sourceURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("assets/brand/app-icon.png")
        let source = try MTKTextureLoader(device: device).newTexture(URL: sourceURL, options: [.SRGB: false])
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 256, height: 256, mipmapped: false)
        targetDescriptor.storageMode = .shared
        targetDescriptor.usage = [.renderTarget]
        let target = try XCTUnwrap(device.makeTexture(descriptor: targetDescriptor))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        func render(time: Float) throws -> [UInt8] {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
            var uniforms = SIMD4<Float>(256, 256, time, 0)
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(source, index: 0)
            encoder.setFragmentBytes(&uniforms, length: 16, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            XCTAssertEqual(command.status, .completed)
            var bytes = [UInt8](repeating: 0, count: 256 * 256 * 4)
            target.getBytes(&bytes, bytesPerRow: 256 * 4, from: MTLRegionMake2D(0, 0, 256, 256), mipmapLevel: 0)
            if let directory = ProcessInfo.processInfo.environment["PUV_ARTWORK_SNAPSHOT_DIR"],
               let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256,
                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                   colorSpaceName: .deviceRGB, bytesPerRow: 1024, bitsPerPixel: 32) {
                for index in stride(from: 0, to: bytes.count, by: 4) { bytes.swapAt(index, index + 2) }
                bitmap.bitmapData?.update(from: bytes, count: bytes.count)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: URL(fileURLWithPath: directory).appendingPathComponent("logo-\(time).png"))
                for index in stride(from: 0, to: bytes.count, by: 4) { bytes.swapAt(index, index + 2) }
            }
            return bytes
        }
        let blank = try render(time: 0)
        let drawing = try render(time: 1.8)
        let settled = try render(time: 4.2)
        XCTAssertNotEqual(blank, drawing)
        XCTAssertNotEqual(drawing, settled)
        XCTAssertEqual(settled, try render(time: 8))
        XCTAssertGreaterThan(settled.filter { $0 > 100 }.count, 10000)
    }
}
