import AppKit

struct FileInfoDetails {
    let name: String
    let kind: String
    let location: String
    let isDirectory: Bool
    let byteCount: Int64?
    let created: Date?
    let modified: Date?
    let isReadable: Bool
    let isWritable: Bool
    let permissions: String
    let owner: String
    let group: String

    init(url: URL) throws {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let values = try url.resourceValues(forKeys: [
            .localizedNameKey, .localizedTypeDescriptionKey, .isDirectoryKey, .fileSizeKey,
            .creationDateKey, .contentModificationDateKey, .isReadableKey, .isWritableKey
        ])
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        name = values.localizedName ?? url.lastPathComponent
        kind = values.localizedTypeDescription ?? L("Unknown")
        location = url.deletingLastPathComponent().path
        isDirectory = values.isDirectory == true
        byteCount = isDirectory ? nil : values.fileSize.map(Int64.init)
        created = values.creationDate
        modified = values.contentModificationDate
        isReadable = values.isReadable ?? FileManager.default.isReadableFile(atPath: url.path)
        isWritable = values.isWritable ?? FileManager.default.isWritableFile(atPath: url.path)
        if let mode = (attributes[.posixPermissions] as? NSNumber)?.uint32Value {
            var symbols = Array("---------")
            let characters = Array("rwxrwxrwx")
            for index in 0..<9 where mode & (1 << (8 - index)) != 0 { symbols[index] = characters[index] }
            for (bit, index, active, inactive) in [(UInt32(0o4000), 2, Character("s"), Character("S")),
                                                  (0o2000, 5, "s", "S"), (0o1000, 8, "t", "T")] {
                if mode & bit != 0 { symbols[index] = symbols[index] == "x" ? active : inactive }
            }
            permissions = String(symbols) + String(format: " (%04o)", mode & 0o7777)
        } else { permissions = L("Unknown") }
        owner = attributes[.ownerAccountName] as? String ?? L("Unknown")
        group = attributes[.groupOwnerAccountName] as? String ?? L("Unknown")
    }
}

final class FileInfoWindowController: NSWindowController, NSWindowDelegate {
    let details: FileInfoDetails
    var onClose: (() -> Void)?

    init(url: URL) throws {
        details = try FileInfoDetails(url: url)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = String(format: L("%@ Info"), details.name)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 360, height: 280)
        super.init(window: window)
        window.delegate = self
        buildContent(url: url, window: window)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let completion = onClose
        onClose = nil
        completion?()
    }

    private func buildContent(url: URL, window: NSWindow) {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let document = FileInfoDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        window.contentView = scroll

        let icon = NSImageView()
        icon.image = NSWorkspace.shared.icon(forFile: url.path)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 48),
                                     icon.heightAnchor.constraint(equalToConstant: 48)])
        let name = valueField(details.name)
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        let header = NSStackView(views: [icon, name])
        header.orientation = .horizontal
        header.spacing = 12
        header.alignment = .centerY

        let date = DateFormatter()
        date.dateStyle = .medium
        date.timeStyle = .short
        let bytes = ByteCountFormatter()
        bytes.countStyle = .file
        bytes.includesActualByteCount = true
        let access: String
        switch (details.isReadable, details.isWritable) {
        case (true, true): access = L("Read & Write")
        case (true, false): access = L("Read Only")
        case (false, true): access = L("Write Only")
        case (false, false): access = L("No Access")
        }
        let rows: [(String, String)] = [
            (L("Kind"), details.kind),
            (L("Size"), details.byteCount.map { bytes.string(fromByteCount: $0) } ?? "—"),
            (L("Where"), details.location),
            (L("Created"), details.created.map { date.string(from: $0) } ?? L("Unknown")),
            (L("Modified"), details.modified.map { date.string(from: $0) } ?? L("Unknown")),
            (L("Access"), access),
            (L("Permissions"), details.permissions),
            (L("Owner"), details.owner),
            (L("Group"), details.group)
        ]
        let grid = NSGridView(views: rows.map { title, value in
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.setContentHuggingPriority(.required, for: .horizontal)
            return [label, valueField(value)]
        })
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).width = 88
        grid.yPlacement = .top
        let separator = NSBox()
        separator.boxType = .separator
        let stack = NSStackView(views: [header, separator, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func valueField(_ value: String) -> NSTextField {
        let field = FileInfoValueField(wrappingLabelWithString: value)
        field.font = .systemFont(ofSize: 13)
        field.textColor = .labelColor
        field.isSelectable = true
        field.isEditable = false
        field.lineBreakMode = .byCharWrapping
        field.preferredMaxLayoutWidth = 268
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
}

private final class FileInfoDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class FileInfoValueField: NSTextField {
    override func layout() {
        super.layout()
        if bounds.width > 0, abs(preferredMaxLayoutWidth - bounds.width) > 0.5 {
            preferredMaxLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
}
