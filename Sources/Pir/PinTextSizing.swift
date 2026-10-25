import AppKit
import CoreText
import PirCore

enum PinTextSizing {
    static let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    static let inset = NSSize(width: 16, height: 18)
    static let minimumSize = NSSize(width: 120, height: 54)
    static let measurementLimit = 4_096

    static func paragraphStyle() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.defaultTabInterval = 28
        return paragraph
    }

    static func maximumSize(available: NSSize) -> NSSize {
        NSSize(width: max(minimumSize.width, floor(min(560, available.width * 0.55))),
               height: max(minimumSize.height, floor(min(420, available.height * 0.6))))
    }

    static func naturalSize(for text: String, available: NSSize) -> NSSize {
        let maximum = maximumSize(available: available)
        // Bound both traversal and layout before handing the full string to TextKit's viewport.
        let prefix = Array(text.utf16.prefix(measurementLimit + 1))
        guard prefix.count <= measurementLimit else { return maximum }
        var sample = String(decoding: prefix, as: UTF16.self)
        if sample.hasSuffix("\n") || sample.hasSuffix("\r") { sample.append("\u{200B}") }
        let attributed = NSAttributedString(string: sample, attributes: [
            .font: font, .paragraphStyle: paragraphStyle()
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let measured = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(), nil,
            CGSize(width: maximum.width - inset.width * 2,
                   height: maximum.height - inset.height * 2), nil
        )
        return NSSize(width: min(maximum.width, max(minimumSize.width, ceil(measured.width) + inset.width * 2 + 1)),
                      height: min(maximum.height, max(minimumSize.height, ceil(measured.height) + inset.height * 2)))
    }
}
