import AppKit
import PirCore

final class PinFilesView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private(set) var content: FilePinContent
    var onChange: ((FilePinContent) -> Void)?
    var onEmpty: (() -> Void)?
    private let collection = FileCollectionView()
    private let flow = FileGridLayout()
    private var flowViewport = NSSize.zero
    private let scroll = NSScrollView()
    private let actions: FilePinActions
    private var referenceObserver: Any?
    private var viewportObserver: Any?
    private var infoWindows: [URL: FileInfoWindowController] = [:]
    private var isRecycling = false
    private let modes = NSSegmentedControl(images: [
        NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)!,
        NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)!
    ], trackingMode: .selectOne, target: nil, action: nil)

    init(content: FilePinContent, actions: FilePinActions = FilePinActions()) {
        self.content = content
        self.actions = actions
        super.init(frame: .zero)
        wantsLayer = true
        modes.target = self
        modes.action = #selector(changeLayout)
        modes.controlSize = .small
        modes.setToolTip(L("Icons"), forSegment: 0)
        modes.setToolTip(L("List"), forSegment: 1)
        modes.setAccessibilityLabel(L("File view"))
        modes.selectedSegment = content.layout == .icons ? 0 : 1
        collection.collectionViewLayout = flow
        collection.dataSource = self
        collection.delegate = self
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = true
        collection.backgroundColors = [.clear]
        collection.autoresizingMask = [.width]
        collection.register(FileCollectionItem.self, forItemWithIdentifier: FileCollectionItem.identifier)
        collection.setDraggingSourceOperationMask([.copy, .move, .link], forLocal: false)
        collection.onOpen = { [weak self] index in self?.openFile(at: index) }
        collection.onContextMenu = { [weak self] in self?.selectionMenu() }
        collection.onOpenSelection = { [weak self] in self?.openSelection() }
        collection.onRename = { [weak self] in self?.renameSelection() }
        collection.onTrash = { [weak self] in self?.trashSelection() }
        collection.onInfo = { [weak self] in self?.showInfo() }
        collection.onCopy = { [weak self] in self?.copySelection() }
        scroll.documentView = collection
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        for child in [modes, scroll] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            modes.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            modes.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 42),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        scroll.contentView.postsFrameChangedNotifications = true
        viewportObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
            object: scroll.contentView, queue: .main) { [weak self] _ in self?.updateFlow() }
        referenceObserver = NotificationCenter.default.addObserver(forName: FilePinReferenceChange.notification, object: nil, queue: .main) { [weak self] note in
            guard let change = note.object as? FilePinReferenceChange else { return }
            self?.apply(change)
        }
        updateFlow()
    }

    deinit {
        if let referenceObserver { NotificationCenter.default.removeObserver(referenceObserver) }
        if let viewportObserver { NotificationCenter.default.removeObserver(viewportObserver) }
        for controller in infoWindows.values { controller.close() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func layout() {
        super.layout()
        updateFlow()
    }

    func setLayout(_ layout: FilePinContent.Layout) {
        content.layout = layout
        modes.selectedSegment = layout == .icons ? 0 : 1
        updateFlow()
        collection.reloadData()
        onChange?(content)
    }

    func removeFiles(at indexes: Set<Int>) {
        content.urls = content.urls.enumerated().filter { !indexes.contains($0.offset) }.map(\.element)
        if content.urls.isEmpty { onEmpty?(); return }
        collection.selectionIndexPaths = []
        collection.reloadData()
        onChange?(content)
    }

    func fileURL(at index: Int) -> URL? {
        content.urls.indices.contains(index) ? content.urls[index] : nil
    }

    func isDragArea(at point: NSPoint) -> Bool {
        point.y >= bounds.maxY - 42 && !modes.frame.contains(point)
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { content.urls.count }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: FileCollectionItem.identifier, for: indexPath)
        (item as? FileCollectionItem)?.configure(content.urls[indexPath.item], layout: content.layout)
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        fileURL(at: indexPath.item).map { $0 as NSURL }
    }

    private func updateFlow() {
        guard flow.mode != content.layout || flowViewport != scroll.contentSize else { return }
        flow.mode = content.layout
        flowViewport = scroll.contentSize
        flow.invalidateLayout()
        collection.needsLayout = true
    }

    private func openFile(at index: Int) {
        guard let url = fileURL(at: index) else { return }
        if !actions.open(url) { showFileError(CocoaError(.fileReadUnknown)) }
    }

    func selectionMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let entries: [(String, String, Selector)] = [
            ("Open", "arrow.up.forward.app", #selector(openSelection)),
            ("Move to Trash", "trash", #selector(trashSelection)),
            ("Get Info", "info.circle", #selector(showInfo)),
            ("Rename", "pencil", #selector(renameSelection)),
            ("Show in Finder", "folder", #selector(revealSelection))
        ]
        for (title, symbol, action) in entries {
            let item = NSMenuItem(title: L(title), action: action, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            item.target = self
            item.isEnabled = !selectedURLs.isEmpty && !isRecycling
            menu.addItem(item)
            if title == "Open" || title == "Move to Trash" { menu.addItem(.separator()) }
        }
        menu.addItem(.separator())
        let remove = menu.addItem(withTitle: L("Remove from list"), action: #selector(removeSelection), keyEquivalent: "")
        remove.target = self
        remove.isEnabled = !selectedURLs.isEmpty && !isRecycling
        return menu
    }

    private var selectedIndexes: Set<Int> { Set(collection.selectionIndexPaths.map(\.item)) }
    private var selectedURLs: [URL] { selectedIndexes.sorted().compactMap(fileURL(at:)) }

    func renameFiles(at indexes: Set<Int>, name: String) throws {
        try renameFiles(urls: indexes.sorted().compactMap(fileURL(at:)), name: name)
    }

    func renameFiles(urls: [URL], name: String) throws {
        do {
            let replacements = try FilePinActions.renamedURLs(urls, name: name)
            NotificationCenter.default.post(name: FilePinReferenceChange.notification,
                                            object: FilePinReferenceChange(replacements: replacements))
        } catch let failure as FilePinRenameFailure {
            NotificationCenter.default.post(name: FilePinReferenceChange.notification,
                                            object: FilePinReferenceChange(replacements: failure.relocated))
            throw failure
        }
    }

    func trashFiles(at indexes: Set<Int>, completion: @escaping (Error?) -> Void) {
        guard !isRecycling else { return }
        let urls = indexes.sorted().compactMap(fileURL(at:))
        guard !urls.isEmpty else { completion(nil); return }
        isRecycling = true
        actions.recycle(urls) { [weak self] moved, error in
            let update = {
                self?.isRecycling = false
                NotificationCenter.default.post(name: FilePinReferenceChange.notification,
                                                object: FilePinReferenceChange(removed: Set(moved.keys)))
                completion(error)
            }
            if Thread.isMainThread { update() }
            else { DispatchQueue.main.async(execute: update) }
        }
    }

    private func apply(_ change: FilePinReferenceChange) {
        let updated = content.urls.compactMap(change.updatedURL)
        guard updated != content.urls else { return }
        content.urls = updated
        if updated.isEmpty { onEmpty?(); return }
        collection.selectionIndexPaths = []
        collection.reloadData()
        onChange?(content)
    }

    private func showFileError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L("File operation failed")
        alert.informativeText = [error.localizedDescription, (error as? LocalizedError)?.recoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
        alert.runModal()
    }

    @objc private func openSelection() {
        let failed = selectedURLs.filter { !actions.open($0) }
        if !failed.isEmpty { showFileError(CocoaError(.fileReadUnknown)) }
    }

    @objc private func trashSelection() {
        trashFiles(at: selectedIndexes) { [weak self] error in if let error { self?.showFileError(error) } }
    }

    @objc private func renameSelection() {
        let urls = selectedURLs
        guard let first = urls.first else { return }
        let alert = NSAlert()
        alert.messageText = L("Rename")
        alert.informativeText = urls.count == 1 ? first.lastPathComponent : L("Selected files will be numbered. File extensions are preserved.")
        let field = NSTextField(string: urls.count == 1 ? first.lastPathComponent : L("File"))
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L("Rename"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try renameFiles(urls: urls, name: field.stringValue) }
        catch { showFileError(error) }
    }

    @objc private func showInfo() {
        for url in selectedURLs {
            do {
                if let existing = infoWindows[url] { existing.present(); continue }
                let controller = try FileInfoWindowController(url: url)
                controller.onClose = { [weak self] in self?.infoWindows.removeValue(forKey: url) }
                infoWindows[url] = controller
                controller.present()
            } catch { showFileError(error) }
        }
    }

    @objc private func revealSelection() { NSWorkspace.shared.activateFileViewerSelecting(selectedURLs) }
    private func copySelection() {
        guard !selectedURLs.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(selectedURLs.map { $0 as NSURL })
    }

    @objc private func changeLayout() { setLayout(modes.selectedSegment == 0 ? .icons : .list) }
    @objc private func removeSelection() { removeFiles(at: Set(collection.selectionIndexPaths.map(\.item))) }
}

private final class FileGridLayout: NSCollectionViewLayout {
    var mode: FilePinContent.Layout = .icons
    private var attributes: [NSCollectionViewLayoutAttributes] = []
    private var size = NSSize.zero

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let count = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
        let viewport: NSSize
        if let scroll = collectionView.enclosingScrollView {
            viewport = PinFileSizing.layoutViewport(actual: scroll.contentSize, scrollFrame: scroll.frame.size,
                style: scroll.scrollerStyle, autohidesScrollers: scroll.autohidesScrollers, count: count, layout: mode)
        } else { viewport = collectionView.bounds.size }
        let columns = mode == .list ? 1 : PinFileSizing.columns(contentWidth: viewport.width)
        let item = mode == .list ? NSSize(width: max(1, viewport.width - 8), height: PinFileSizing.listRowHeight) : PinFileSizing.itemSize
        let gap = mode == .list ? 4.0 : PinFileSizing.spacing
        attributes = (0..<count).map { index in
            let value = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
            value.frame = NSRect(x: PinFileSizing.contentInset + CGFloat(index % columns) * (item.width + gap),
                                 y: PinFileSizing.contentInset + CGFloat(index / columns) * (item.height + gap),
                                 width: item.width, height: item.height)
            return value
        }
        size = NSSize(width: viewport.width, height: max(viewport.height,
            PinFileSizing.documentHeight(count: count, layout: mode, viewportWidth: viewport.width)))
    }

    override var collectionViewContentSize: NSSize { size }
    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        attributes.filter { $0.frame.intersects(rect) }
    }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        attributes.indices.contains(indexPath.item) ? attributes[indexPath.item] : nil
    }
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        newBounds.size != collectionView?.bounds.size
    }
}

final class FileCollectionView: NSCollectionView {
    var onOpen: ((Int) -> Void)?
    var onContextMenu: (() -> NSMenu?)?
    var onOpenSelection: (() -> Void)?
    var onRename: (() -> Void)?
    var onTrash: (() -> Void)?
    var onInfo: (() -> Void)?
    var onCopy: (() -> Void)?
    private let selectionBand = CAShapeLayer()

    override func mouseDown(with event: NSEvent) {
        let start = convert(event.locationInWindow, from: nil)
        if indexPathForItem(at: start) == nil, let window {
            window.makeFirstResponder(self)
            let initial = selectionIndexPaths
            let modifiers = event.modifierFlags.intersection([.command, .shift])
            if modifiers.isEmpty { selectionIndexPaths = [] }
            wantsLayer = true
            selectionBand.fillColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.15).cgColor
            selectionBand.strokeColor = NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.8).cgColor
            selectionBand.lineWidth = 1
            layer?.addSublayer(selectionBand)
            defer { selectionBand.removeFromSuperlayer() }
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                if next.type == .leftMouseUp { break }
                autoscroll(with: next)
                let point = convert(next.locationInWindow, from: nil)
                let rect = NSRect(x: min(start.x, point.x), y: min(start.y, point.y),
                                  width: abs(point.x - start.x), height: abs(point.y - start.y))
                updateBandSelection(in: rect, initial: initial, modifiers: modifiers)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                selectionBand.path = CGPath(rect: rect, transform: nil)
                CATransaction.commit()
            }
            return
        }
        super.mouseDown(with: event)
        if event.clickCount == 2, let path = indexPathForItem(at: convert(event.locationInWindow, from: nil)) {
            onOpen?(path.item)
        }
    }

    func updateBandSelection(in rect: NSRect, initial: Set<IndexPath>, modifiers: NSEvent.ModifierFlags) {
        let intersecting = Set((collectionViewLayout?.layoutAttributesForElements(in: rect) ?? [])
            .filter { $0.representedElementCategory == .item && $0.frame.insetBy(dx: 4, dy: 4).intersects(rect) }
            .compactMap(\.indexPath))
        if modifiers.contains(.command) { selectionIndexPaths = initial.symmetricDifference(intersecting) }
        else if modifiers.contains(.shift) { selectionIndexPaths = initial.union(intersecting) }
        else { selectionIndexPaths = intersecting }
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 36, modifiers.isEmpty { onRename?(); return }
        if modifiers == .command {
            switch event.keyCode {
            case 31, 125: onOpenSelection?(); return
            case 34: onInfo?(); return
            case 51: onTrash?(); return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    @objc func copy(_ sender: Any?) { onCopy?() }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let path = indexPathForItem(at: convert(event.locationInWindow, from: nil)) else { return nil }
        if !selectionIndexPaths.contains(path) { selectionIndexPaths = [path] }
        return onContextMenu?()
    }

    override func cursorUpdate(with event: NSEvent) {
        guard let surface = enclosingScrollView?.superview?.superview as? PinSurface else { return }
        surface.resizeCursor(at: surface.convert(event.locationInWindow, from: nil)).set()
    }
}

private final class FileCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("file-pin-item")
    private let icon = NSImageView()
    private let name = NSTextField(wrappingLabelWithString: "")
    private let stack = NSStackView()
    private var layoutMode: FilePinContent.Layout = .icons
    private var iconWidth: NSLayoutConstraint!
    private var iconHeight: NSLayoutConstraint!

    override var isSelected: Bool { didSet { updateSelection() } }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        name.font = .systemFont(ofSize: 11)
        name.maximumNumberOfLines = 2
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 6
        name.wantsLayer = true
        name.layer?.cornerRadius = 4
        name.layer?.masksToBounds = true
        stack.spacing = 4
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(name)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        iconWidth = icon.widthAnchor.constraint(equalToConstant: 40)
        iconHeight = icon.heightAnchor.constraint(equalToConstant: 40)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            iconWidth, iconHeight
        ])
    }

    func configure(_ url: URL, layout: FilePinContent.Layout) {
        _ = view
        layoutMode = layout
        icon.image = NSWorkspace.shared.icon(forFile: url.path)
        name.stringValue = url.lastPathComponent
        view.toolTip = url.path
        stack.orientation = layout == .list ? .horizontal : .vertical
        stack.alignment = layout == .list ? .centerY : .centerX
        iconWidth.constant = layout == .list ? 24 : PinFileSizing.iconSize
        iconHeight.constant = iconWidth.constant
        name.alignment = layout == .list ? .left : .center
        name.maximumNumberOfLines = layout == .list ? 1 : 2
        updateSelection()
    }

    private func updateSelection() {
        let listSelection = isSelected && layoutMode == .list
        view.layer?.backgroundColor = listSelection ? NSColor.selectedContentBackgroundColor.cgColor : NSColor.clear.cgColor
        icon.layer?.borderWidth = isSelected && layoutMode == .icons ? 2 : 0
        icon.layer?.borderColor = NSColor.secondaryLabelColor.withAlphaComponent(0.5).cgColor
        name.drawsBackground = isSelected && layoutMode == .icons
        name.backgroundColor = .selectedContentBackgroundColor
        name.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
    }
}
