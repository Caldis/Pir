import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum ClipboardContent {
    case image(NSImage)
    case text(String)
    case files(FilePinContent)
}

public enum ClipboardError: Error { case unsupported, tooLarge }

public enum ClipboardReader {
    public static let maximumImageDimension = 4096
    public static let maximumTextBytes = 4 * 1024 * 1024
    public static let maximumImageBytes = 64 * 1024 * 1024
    public static let maximumFileCount = 512

    public static func read(from pasteboard: NSPasteboard = .general) throws -> ClipboardContent {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            guard urls.count <= maximumFileCount else { throw ClipboardError.tooLarge }
            return .files(FilePinContent(urls: urls))
        }
        var rejectedLargeContent = false
        // Image representations precede text because browsers commonly provide both.
        // TIFF preserves the logical size of Retina screenshots when a PNG fallback drops its DPI.
        let preferredTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
        let additionalTypes = (pasteboard.types ?? []).filter {
            !preferredTypes.contains($0) && UTType($0.rawValue)?.conforms(to: .image) == true
        }
        for type in preferredTypes + additionalTypes {
            guard let data = pasteboard.data(forType: type) else { continue }
            guard data.count <= maximumImageBytes else {
                rejectedLargeContent = true
                continue
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumImageDimension,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { continue }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? Double(image.width)
            let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? Double(image.height)
            let dpiWidth = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
            let dpiHeight = (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue ?? 72
            var pointSize = NSSize(width: pixelWidth * 72 / (dpiWidth.isFinite && dpiWidth > 0 ? dpiWidth : 72),
                                   height: pixelHeight * 72 / (dpiHeight.isFinite && dpiHeight > 0 ? dpiHeight : 72))
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            if (5...8).contains(orientation) { pointSize = NSSize(width: pointSize.height, height: pointSize.width) }
            // Bitmap downsampling changes representation pixels, not the source's display size in points.
            let representation = NSBitmapImageRep(cgImage: image)
            representation.size = pointSize
            let result = NSImage(size: pointSize)
            result.addRepresentation(representation)
            return .image(result)
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            guard text.utf8.count <= maximumTextBytes else { throw ClipboardError.tooLarge }
            return .text(text)
        }
        if let data = pasteboard.data(forType: .rtf) {
            guard data.count <= maximumTextBytes else { throw ClipboardError.tooLarge }
            if let text = NSAttributedString(rtf: data, documentAttributes: nil)?.string, !text.isEmpty {
                return .text(text)
            }
        }
        throw rejectedLargeContent ? ClipboardError.tooLarge : ClipboardError.unsupported
    }
}
