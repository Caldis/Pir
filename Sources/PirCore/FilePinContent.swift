import Foundation

public struct FilePinContent: Codable, Equatable {
    public enum Layout: String, Codable { case icons, list }
    public var urls: [URL]
    public var layout: Layout

    public init(urls: [URL], layout: Layout = .icons) {
        self.urls = urls
        self.layout = layout
    }

    public var isValid: Bool {
        !urls.isEmpty && urls.count <= ClipboardReader.maximumFileCount && urls.allSatisfy(\.isFileURL)
    }
}
