import AppKit

struct FilePinActions {
    var open: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    var recycle: ([URL], @escaping ([URL: URL], Error?) -> Void) -> Void = {
        NSWorkspace.shared.recycle($0, completionHandler: $1)
    }

    static func renamedURLs(_ urls: [URL], name: String) throws -> [URL: URL] {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.contains("\0") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let manager = FileManager.default
        var seen: Set<URL> = []
        let sources = urls.filter { seen.insert($0).inserted }
        var plan: [(source: URL, destination: URL, temporary: URL)] = []
        for (index, source) in sources.enumerated() {
            let directory = try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            let suffix = !directory && !source.pathExtension.isEmpty ? "." + source.pathExtension : ""
            let filename = sources.count == 1 ? name : "\(name) \(index + 1)\(suffix)"
            let destination = source.deletingLastPathComponent().appendingPathComponent(filename, isDirectory: directory)
            if destination == source { continue }
            if manager.fileExists(atPath: destination.path), !sources.contains(destination) {
                let sourceID = try source.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject
                let destinationID = try destination.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject
                guard sourceID != nil, sourceID == destinationID else { throw CocoaError(.fileWriteFileExists) }
            }
            let temporary = source.deletingLastPathComponent().appendingPathComponent(".pir-rename-\(UUID().uuidString)")
            plan.append((source, destination, temporary))
        }
        var staged: [Int] = []
        var completed: [Int] = []
        do {
            for index in plan.indices {
                try manager.moveItem(at: plan[index].source, to: plan[index].temporary)
                staged.append(index)
            }
            for index in plan.indices {
                try manager.moveItem(at: plan[index].temporary, to: plan[index].destination)
                completed.append(index)
            }
        } catch {
            // Staging the completed destinations first also restores case-only names and swaps.
            for index in completed.reversed() { try? manager.moveItem(at: plan[index].destination, to: plan[index].temporary) }
            for index in staged.reversed() { try? manager.moveItem(at: plan[index].temporary, to: plan[index].source) }
            var relocated: [URL: URL] = [:]
            for item in plan where !manager.fileExists(atPath: item.source.path) {
                if manager.fileExists(atPath: item.temporary.path) { relocated[item.source] = item.temporary }
                else if manager.fileExists(atPath: item.destination.path) { relocated[item.source] = item.destination }
            }
            throw FilePinRenameFailure(underlying: error, relocated: relocated)
        }
        return Dictionary(uniqueKeysWithValues: plan.map { ($0.source, $0.destination) })
    }
}

struct FilePinRenameFailure: LocalizedError {
    let underlying: Error
    let relocated: [URL: URL]
    var errorDescription: String? { underlying.localizedDescription }
    var recoverySuggestion: String? {
        relocated.isEmpty ? nil : L("Files remain at these locations:") + "\n" + relocated.values.map(\.path).sorted().joined(separator: "\n")
    }
}

struct FilePinReferenceChange {
    static let notification = Notification.Name("me.caldis.pir.fileReferencesChanged")
    var replacements: [URL: URL] = [:]
    var removed: Set<URL> = []

    func updatedURL(_ url: URL) -> URL? {
        let components = url.standardizedFileURL.pathComponents
        func contains(_ ancestor: URL) -> Bool {
            let prefix = ancestor.standardizedFileURL.pathComponents
            return components.starts(with: prefix)
        }
        if removed.contains(where: contains) { return nil }
        guard let source = replacements.keys.filter(contains).max(by: {
            $0.pathComponents.count < $1.pathComponents.count
        }), let destination = replacements[source] else { return url }
        return components.dropFirst(source.standardizedFileURL.pathComponents.count).reduce(destination) {
            $0.appendingPathComponent($1)
        }
    }
}
