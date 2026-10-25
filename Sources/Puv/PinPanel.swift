import AppKit
import PuvCore
import OSLog

final class PinPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    var onClose: (() -> Void)?
    var onFrameChange: ((NSRect) -> Void)?
    private let naturalSize: NSSize

    init(content: ClipboardContent, screen: NSScreen, offset: Int, restoredFrame: NSRect? = nil) {
        let preferred: NSSize
        switch content {
        case .image(let image): preferred = image.size
        case .text: preferred = NSSize(width: 420, height: 300)
        }
        naturalSize = preferred
        let size = PinGeometry.initialSize(content: preferred, available: screen.visibleFrame.size)
        let visible = screen.visibleFrame
        let stagger = CGFloat(offset % 8) * 22
        let origin = NSPoint(x: min(visible.maxX - size.width, visible.midX - size.width / 2 + stagger),
                             y: max(visible.minY, visible.midY - size.height / 2 - stagger))
        super.init(contentRect: restoredFrame ?? NSRect(origin: origin, size: size),
                   styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        minSize = PinGeometry.minimumSize
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        let surface = PinSurface(content: content)
        surface.onClose = { [weak self] in self?.close() }
        surface.onRestore = { [weak self] in self?.restoreNaturalSize() }
        contentView = surface
        setAccessibilityLabel(L("Pinned clipboard content"))
        setAccessibilityHelp(L("Drag to move. Drag any edge to resize. Use the close button to dismiss."))
    }

    override func close() {
        super.close()
        onClose?()
        onClose = nil
    }

    func userDidChangeFrame() { onFrameChange?(frame) }

    func restoreNaturalSize() {
        guard let screen = screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = PinGeometry.initialSize(content: naturalSize, available: visible.size)
        let origin = NSPoint(x: min(max(frame.minX, visible.minX), visible.maxX - size.width),
                             y: min(max(frame.maxY - size.height, visible.minY), visible.maxY - size.height))
        setFrame(NSRect(origin: origin, size: size), display: true)
        userDidChangeFrame()
    }
}

private final class PinSurface: NSView {
    private let closeButton = NSButton()
    private let restoreButton = NSButton()
    private let controls = NSStackView()
    private let resizeInset: CGFloat = 13
    private var tracking: NSTrackingArea?
    var onClose: (() -> Void)?
    var onRestore: (() -> Void)?

    init(content: ClipboardContent) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        let body: NSView
        switch content {
        case .image(let image):
            body = PinImageView(image: image)
        case .text(let text):
            let scroll = PinTextScrollView()
            scroll.borderType = .noBorder
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.autohidesScrollers = true
            scroll.drawsBackground = true
            scroll.backgroundColor = .textBackgroundColor
            let view = PinTextView(usingTextLayoutManager: true)
            view.frame = NSRect(x: 0, y: 0, width: 420, height: 300)
            view.isEditable = false
            view.isSelectable = false
            view.isRichText = false
            view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
            view.textColor = .textColor
            view.backgroundColor = .textBackgroundColor
            view.textContainerInset = NSSize(width: 16, height: 18)
            view.isVerticallyResizable = true
            view.isHorizontallyResizable = false
            // NSTextView otherwise retains its initial minimum width and clips narrow windows.
            view.minSize = NSSize(width: 0, height: 0)
            view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            view.autoresizingMask = []
            view.textContainer?.widthTracksTextView = true
            view.textContainer?.containerSize = NSSize(width: 420, height: CGFloat.greatestFiniteMagnitude)
            view.textContainer?.lineFragmentPadding = 0
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byCharWrapping
            paragraph.defaultTabInterval = 28
            view.defaultParagraphStyle = paragraph
            // Accessing layoutManager would opt this view out of TextKit 2's viewport layout.
            view.string = text
            view.setAccessibilityLabel(L("Pinned text"))
            scroll.documentView = view
            body = scroll
        }
        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: leadingAnchor), body.trailingAnchor.constraint(equalTo: trailingAnchor),
            body.topAnchor.constraint(equalTo: topAnchor), body.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L("Close pin"))
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closePin)
        closeButton.toolTip = L("Close pin")
        closeButton.identifier = NSUserInterfaceItemIdentifier("close-pin")
        closeButton.setAccessibilityLabel(L("Close pin"))
        restoreButton.image = NSImage(systemSymbolName: "arrow.counterclockwise.circle.fill", accessibilityDescription: L("Restore natural size"))
        restoreButton.contentTintColor = .secondaryLabelColor
        restoreButton.bezelStyle = .circular
        restoreButton.isBordered = false
        restoreButton.target = self
        restoreButton.action = #selector(restoreSize)
        restoreButton.toolTip = L("Restore natural size")
        restoreButton.identifier = NSUserInterfaceItemIdentifier("restore-pin")
        restoreButton.setAccessibilityLabel(L("Restore natural size"))
        controls.orientation = .horizontal
        controls.spacing = 4
        controls.addArrangedSubview(restoreButton)
        controls.addArrangedSubview(closeButton)
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.isHidden = true
        addSubview(controls)
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 22), closeButton.heightAnchor.constraint(equalToConstant: 22),
            restoreButton.widthAnchor.constraint(equalToConstant: 22), restoreButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func closePin() { onClose?() }
    @objc private func restoreSize() { onRestore?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        controls.isHidden = false
        layoutSubtreeIfNeeded()
        window?.invalidateCursorRects(for: self)
    }
    override func mouseExited(with event: NSEvent) {
        controls.isHidden = true
        window?.invalidateCursorRects(for: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if !controls.isHidden {
            for button in [closeButton, restoreButton] where button.convert(button.bounds, to: self).contains(local) {
                return button
            }
            if controls.frame.contains(local) { return controls }
        }
        if bounds.contains(local), !edges(at: local).isEmpty { return self }
        return super.hitTest(point)
    }

    private func edges(at point: NSPoint) -> ResizeEdges {
        var result: ResizeEdges = []
        if point.x < resizeInset { result.insert(.left) }
        else if point.x > bounds.width - resizeInset { result.insert(.right) }
        if point.y < resizeInset { result.insert(.bottom) }
        else if point.y > bounds.height - resizeInset { result.insert(.top) }
        return result
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let d = resizeInset
        addCursorRect(NSRect(x: 0, y: d, width: d, height: max(0, bounds.height - d * 2)), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.width - d, y: d, width: d, height: max(0, bounds.height - d * 2)), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: d, y: 0, width: max(0, bounds.width - d * 2), height: d), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: d, y: bounds.height - d, width: max(0, bounds.width - d * 2), height: d), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: 0, width: d, height: d), cursor: Self.diagonalUp)
        addCursorRect(NSRect(x: bounds.width - d, y: bounds.height - d, width: d, height: d), cursor: Self.diagonalUp)
        addCursorRect(NSRect(x: 0, y: bounds.height - d, width: d, height: d), cursor: Self.diagonalDown)
        addCursorRect(NSRect(x: bounds.width - d, y: 0, width: d, height: d), cursor: Self.diagonalDown)
        if !controls.isHidden {
            for button in [closeButton, restoreButton] { addCursorRect(button.convert(button.bounds, to: self), cursor: .arrow) }
        }
    }

    private static let diagonalUp: NSCursor = {
        if #available(macOS 15, *) { return .frameResize(position: .topRight, directions: .all) }
        return diagonalCursor("arrow.up.right.and.arrow.down.left")
    }()
    private static let diagonalDown: NSCursor = {
        if #available(macOS 15, *) { return .frameResize(position: .topLeft, directions: .all) }
        return diagonalCursor("arrow.up.left.and.arrow.down.right")
    }()
    private static func diagonalCursor(_ symbol: String) -> NSCursor {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 20, height: 20))
        image.size = NSSize(width: 20, height: 20)
        return NSCursor(image: image, hotSpot: NSPoint(x: 10, y: 10))
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let selectedEdges = edges(at: convert(event.locationInWindow, from: nil))
        guard !selectedEdges.isEmpty else {
            window.performDrag(with: event)
            (window as? PinPanel)?.userDidChangeFrame()
            return
        }
        let initialFrame = window.frame
        let start = window.convertPoint(toScreen: event.locationInWindow)
        // Window coordinates move during left/bottom resizing; deltas use screen coordinates.
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let current = window.convertPoint(toScreen: next.locationInWindow)
            let frame = PinGeometry.resize(frame: initialFrame,
                                           delta: NSPoint(x: current.x - start.x, y: current.y - start.y),
                                           edges: selectedEdges)
            window.setFrame(frame, display: true)
        }
        (window as? PinPanel)?.userDidChangeFrame()
    }
}

final class PinImageView: NSView {
    init(image: NSImage) {
        super.init(frame: .zero)
        wantsLayer = true
        // Use the retained bitmap directly; resolving NSImage at a large point size can upscale it.
        layer?.contents = image.representations.compactMap { ($0 as? NSBitmapImageRep)?.cgImage }.first
            ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
        layer?.minificationFilter = .trilinear
        layer?.magnificationFilter = .linear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class PinTextScrollView: NSScrollView {
    override func tile() {
        super.tile()
        synchronizeTextWidth()
    }

    override func layout() {
        super.layout()
        synchronizeTextWidth()
    }

    private func synchronizeTextWidth() {
        guard let text = documentView as? NSTextView else { return }
        let width = contentView.bounds.width
        guard width > 0, abs(text.frame.width - width) > 0.5 else { return }
        // Older AppKit versions preserve the pre-attachment width during clip-view autoresizing.
        text.setFrameSize(NSSize(width: width, height: text.frame.height))
    }
}

private final class PinTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
        (window as? PinPanel)?.userDidChangeFrame()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        textColor = .textColor
        backgroundColor = .textBackgroundColor
        enclosingScrollView?.backgroundColor = .textBackgroundColor
    }
}
