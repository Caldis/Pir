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
    private let modes = NSSegmentedControl(images: [
        NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)!,
        NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)!
    ], trackingMode: .selectOne, target: nil, action: nil)

    init(content: FilePinContent) {
        self.content = content
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
        collection.backgroundColors = [.clear]
        collection.autoresizingMask = [.width]
        collection.register(FileCollectionItem.self, forItemWithIdentifier: FileCollectionItem.identifier)
        collection.setDraggingSourceOperationMask([.copy, .move, .link], forLocal: false)
        collection.onOpen = { [weak self] index in self?.openFile(at: index) }
        collection.onContextMenu = { [weak self] in self?.selectionMenu() }
        scroll.documentView = collection
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        for child in [modes, scroll] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            modes.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            modes.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 42),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        updateFlow()
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
        collection.reloadData()
        onChange?(content)
    }

    func fileURL(at index: Int) -> URL? {
        content.urls.indices.contains(index) ? content.urls[index] : nil
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
    }

    private func openFile(at index: Int) {
        guard let url = fileURL(at: index), NSWorkspace.shared.open(url) else { NSSound.beep(); return }
    }

    private func selectionMenu() -> NSMenu {
        let menu = NSMenu()
        let remove = NSMenuItem(title: L("Remove from list"), action: #selector(removeSelection), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        return menu
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
        let viewport = collectionView.enclosingScrollView?.contentSize ?? collectionView.bounds.size
        let columns = mode == .list ? 1 : PinFileSizing.columns(contentWidth: viewport.width)
        let item = mode == .list ? NSSize(width: max(1, viewport.width - 8), height: PinFileSizing.listRowHeight) : PinFileSizing.itemSize
        let gap = mode == .list ? 4.0 : PinFileSizing.spacing
        let count = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
        attributes = (0..<count).map { index in
            let value = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
            value.frame = NSRect(x: 4 + CGFloat(index % columns) * (item.width + gap),
                                 y: 4 + CGFloat(index / columns) * (item.height + gap),
                                 width: item.width, height: item.height)
            return value
        }
        size = NSSize(width: viewport.width, height: max(viewport.height, (attributes.last?.frame.maxY ?? 0) + 4))
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

private final class FileCollectionView: NSCollectionView {
    var onOpen: ((Int) -> Void)?
    var onContextMenu: (() -> NSMenu?)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2, let path = indexPathForItem(at: convert(event.locationInWindow, from: nil)) {
            onOpen?(path.item)
        }
    }

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
        view.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3).cgColor : NSColor.clear.cgColor
    }
}
