import CoreGraphics

enum PinImageAppearance {
    static func hasTransparentEdges(in image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let width = image.width
        let height = image.height
        let edges = [
            CGRect(x: 0, y: 0, width: width, height: 1),
            CGRect(x: 0, y: height - 1, width: width, height: 1),
            CGRect(x: 0, y: 0, width: 1, height: height),
            CGRect(x: width - 1, y: 0, width: 1, height: height)
        ]
        // Edge strips bound scratch memory to the perimeter, independent of image area.
        for rect in edges {
            guard let edge = image.cropping(to: rect),
                  let context = CGContext(data: nil, width: edge.width, height: edge.height,
                                          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                  let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return true }
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(edge, in: CGRect(x: 0, y: 0, width: edge.width, height: edge.height))
            for y in 0..<edge.height {
                for x in 0..<edge.width where data[y * context.bytesPerRow + x * 4 + 3] < 254 { return true }
            }
        }
        return false
    }
}
