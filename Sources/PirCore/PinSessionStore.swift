import Foundation

public struct PinRecord: Codable, Equatable {
    public enum Kind: String, Codable { case image, text, files }
    public let id: UUID
    public let kind: Kind
    public var anchor: PinAnchor
    public let imagePointSize: CGSize?
    public let createdAt: Date
    public var isHidden: Bool
    public var imageScaling: PinImageScaling

    public init(id: UUID, kind: Kind, anchor: PinAnchor, imagePointSize: CGSize?, createdAt: Date = Date(), isHidden: Bool = false,
                imageScaling: PinImageScaling = .cover) {
        self.id = id
        self.kind = kind
        self.anchor = anchor
        self.imagePointSize = imagePointSize
        self.createdAt = createdAt
        self.isHidden = isHidden
        self.imageScaling = imageScaling
    }

    private enum CodingKeys: String, CodingKey { case id, kind, anchor, imagePointSize, createdAt, isHidden, imageScaling }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(Kind.self, forKey: .kind)
        anchor = try values.decode(PinAnchor.self, forKey: .anchor)
        imagePointSize = try values.decodeIfPresent(CGSize.self, forKey: .imagePointSize)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        isHidden = try values.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        imageScaling = (try? values.decode(PinImageScaling.self, forKey: .imageScaling)) ?? .cover
    }
}

public struct StoredPin {
    public let record: PinRecord
    public let data: Data
}

public protocol PinSessionStorage: AnyObject {
    func writeContent(_ data: Data, for id: UUID) throws
    func save(_ records: [PinRecord], removingMissing: Bool) throws
    func load() throws -> [StoredPin]
    func remove(_ id: UUID) throws
}

// The caller serializes content and metadata writes on its I/O queue.
public final class PinSessionStore: PinSessionStorage {
    public let root: URL
    private let manager = FileManager.default
    public static let maximumStoredBytes = 256 * 1024 * 1024

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/pir", isDirectory: true)) {
        self.root = root
    }

    public func writeContent(_ data: Data, for id: UUID) throws {
        try prepareDirectory()
        try writePrivate(data, to: url(id, suffix: "content"))
    }

    public func save(_ records: [PinRecord], removingMissing: Bool = true) throws {
        try prepareDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for record in records { try writePrivate(encoder.encode(record), to: url(record.id, suffix: "json")) }
        guard removingMissing else { return }
        let live = Set(records.map(\.id))
        for file in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            guard ["json", "content"].contains(file.pathExtension),
                  let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), !live.contains(id) else { continue }
            try manager.removeItem(at: file)
        }
    }

    public func remove(_ id: UUID) throws {
        for suffix in ["json", "content"] {
            let file = url(id, suffix: suffix)
            if manager.fileExists(atPath: file.path) { try manager.removeItem(at: file) }
        }
    }

    public func load() throws -> [StoredPin] {
        guard manager.fileExists(atPath: root.path) else { return [] }
        try prepareDirectory()
        let decoder = JSONDecoder()
        var result: [StoredPin] = []
        var totalBytes = 0
        for file in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey]) where file.pathExtension == "json" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let metadataSize = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, metadataSize <= 16_384,
                  let metadata = try? Data(contentsOf: file), let record = try? decoder.decode(PinRecord.self, from: metadata),
                  record.id == id, record.anchor.isValid else { continue }
            let contentURL = url(id, suffix: "content")
            let limit = record.kind == .image ? ClipboardReader.maximumImageBytes : ClipboardReader.maximumTextBytes
            guard let bytes = try? contentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  (bytes > 0 || record.kind == .text), bytes <= limit, totalBytes + bytes <= Self.maximumStoredBytes,
                  let data = try? Data(contentsOf: contentURL) else { continue }
            totalBytes += bytes
            result.append(StoredPin(record: record, data: data))
        }
        return result.sorted { $0.record.createdAt < $1.record.createdAt }
    }

    private func url(_ id: UUID, suffix: String) -> URL { root.appendingPathComponent(id.uuidString + "." + suffix) }

    private func prepareDirectory() throws {
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }

    private func writePrivate(_ data: Data, to destination: URL) throws {
        let temporary = root.appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }
        guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // Same-directory rename keeps either the previous complete file or the new complete file visible.
        let result = temporary.path.withCString { source in destination.path.withCString { target in rename(source, target) } }
        if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
