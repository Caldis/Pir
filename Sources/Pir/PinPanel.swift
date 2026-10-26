import AppKit
import PirCore
import OSLog

final class PinPanel: NSPanel {
    override var canBecomeKey: Bool { acceptsKeyboardInput }
    override var canBecomeMain: Bool { false }
    var onClose: (() -> Void)?
    var onFrameChange: ((NSRect) -> Void)?
    var onTextChange: ((String) -> Void)?
    var acceptsTextSize: ((Int) -> Bool)?
    var onFilesChange: ((FilePinContent) -> Void)?
    private let naturalSize: NSSize
    private var naturalText: String?
    private var naturalFiles: FilePinContent?
    private let acceptsKeyboardInput: Bool

    init(content: ClipboardContent, screen: NSScreen, offset: Int, restoredFrame: NSRect? = nil) {
        let preferred: NSSize
        if case .image = content { acceptsKeyboardInput = false } else { acceptsKeyboardInput = true }
        switch content {
        case .image(let image):
            preferred = image.size
            naturalText = nil
        case .files(let files):
            preferred = PinFileSizing.naturalSize(for: files, available: screen.visibleFrame.size)
            naturalFiles = files
            naturalText = nil
        case .text(let text):
            preferred = PinTextSizing.naturalSize(for: text, available: screen.visibleFrame.size)
            naturalText = text
        }
        naturalSize = preferred
        let minimum: NSSize
        if case .files(let files) = content { minimum = PinFileSizing.minimumSize(for: files.layout) }
        else { minimum = naturalText == nil ? PinGeometry.minimumSize : PinTextSizing.minimumSize }
        let size = PinGeometry.initialSize(content: preferred, available: screen.visibleFrame.size, minimum: minimum)
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
        minSize = minimum
        backgroundColor = .clear
        isOpaque = false
        acceptsMouseMovedEvents = true
        let surface = PinSurface(content: content)
        // WindowServer derives its shadow outline from content alpha, including captured shadows.
        hasShadow = surface.usesWindowShadow
        surface.onClose = { [weak self] in self?.close() }
        surface.onRestore = { [weak self] in self?.restoreNaturalSize() }
        surface.onTextChange = { [weak self] text in
            self?.naturalText = text
            self?.onTextChange?(text)
        }
        surface.onFilesChange = { [weak self] files in
            guard let self else { return }
            naturalFiles = files
            minSize = PinFileSizing.minimumSize(for: files.layout)
            onFilesChange?(files)
            fitFileHeight()
        }
        surface.acceptsTextSize = { [weak self] bytes in self?.acceptsTextSize?(bytes) ?? true }
        contentView = surface
        setAccessibilityLabel(L("Pinned clipboard content"))
        setAccessibilityHelp(L(naturalText == nil ? "Drag to move. Drag any edge to resize. Use the close button to dismiss."
            : "Select and edit text. Drag the top margin to move. Drag any edge to resize."))
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
        let preferred = naturalFiles.map { PinFileSizing.naturalSize(for: $0, available: visible.size) }
            ?? naturalText.map { PinTextSizing.naturalSize(for: $0, available: visible.size) } ?? naturalSize
        let size = PinGeometry.initialSize(content: preferred, available: visible.size, minimum: minSize)
        let origin = NSPoint(x: min(max(frame.minX, visible.minX), visible.maxX - size.width),
                             y: min(max(frame.maxY - size.height, visible.minY), visible.maxY - size.height))
        setFrame(NSRect(origin: origin, size: size), display: true)
        userDidChangeFrame()
    }

    private func fitFileHeight() {
        guard let files = naturalFiles, let screen = screen ?? NSScreen.main else { return }
        let size = PinFileSizing.naturalSize(for: files, available: screen.visibleFrame.size, width: frame.width)
        var frame = frame
        frame.origin.y = max(screen.visibleFrame.minY, frame.maxY - size.height)
        frame.size.height = size.height
        setFrame(frame, display: true)
        userDidChangeFrame()
    }
}

final class PinSurface: NSView, NSTextViewDelegate {
    private(set) var usesWindowShadow = true
    private let closeButton = PinControlButton()
    private let restoreButton = PinControlButton()
    private let copyButton = PinControlButton()
    private let content: ClipboardContent
    private var textEditor: NSTextView?
    private var filesView: PinFilesView?
    private let controls = NSStackView()
    private let controlsBackdrop = PinControlsBackdrop()
    private let hoverOutline = PinHoverOutline()
    static let resizeInset: CGFloat = 6.5
    private var tracking: NSTrackingArea?
    var onClose: (() -> Void)?
    var onRestore: (() -> Void)?
    var onTextChange: ((String) -> Void)?
    var acceptsTextSize: ((Int) -> Bool)?
    var onFilesChange: ((FilePinContent) -> Void)?

    init(content: ClipboardContent) {
        self.content = content
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true

        let body: NSView
        switch content {
        case .image(let image):
            let imageView = PinImageView(image: image)
            usesWindowShadow = !imageView.hasTransparentEdges
            body = imageView
        case .files(let files):
            let view = PinFilesView(content: files)
            view.onChange = { [weak self] value in self?.onFilesChange?(value) }
            view.onEmpty = { [weak self] in self?.onClose?() }
            filesView = view
            body = view
        case .text(let text):
            let scroll = PinTextScrollView()
            scroll.contentView = PinTextClipView()
            scroll.borderType = .noBorder
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            scroll.contentView.drawsBackground = false
            let view = PinTextView(usingTextLayoutManager: true)
            view.frame = NSRect(origin: .zero, size: PinTextSizing.minimumSize)
            view.isEditable = true
            view.isSelectable = true
            view.allowsUndo = true
            view.delegate = self
            textEditor = view
            view.isRichText = false
            view.font = PinTextSizing.font
            view.textColor = .textColor
            view.drawsBackground = false
            view.textContainerInset = PinTextSizing.inset
            view.isVerticallyResizable = true
            view.isHorizontallyResizable = false
            // NSTextView otherwise retains its initial minimum width and clips narrow windows.
            view.minSize = NSSize(width: 0, height: 0)
            view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            view.autoresizingMask = []
            view.textContainer?.widthTracksTextView = true
            view.textContainer?.containerSize = NSSize(width: PinGeometry.minimumSize.width, height: CGFloat.greatestFiniteMagnitude)
            view.textContainer?.lineFragmentPadding = 0
            view.defaultParagraphStyle = PinTextSizing.paragraphStyle()
            // Accessing layoutManager would opt this view out of TextKit 2's viewport layout.
            view.string = text
            view.setAccessibilityLabel(L("Pinned text"))
            scroll.documentView = view
            body = scroll
        }
        layer?.cornerRadius = usesWindowShadow ? 10 : 0
        if filesView != nil || textEditor != nil {
            let material = PreferencesStyle.background(height: 0)
            material.translatesAutoresizingMaskIntoConstraints = false
            addSubview(material)
            NSLayoutConstraint.activate([
                material.leadingAnchor.constraint(equalTo: leadingAnchor),
                material.trailingAnchor.constraint(equalTo: trailingAnchor),
                material.topAnchor.constraint(equalTo: topAnchor),
                material.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: leadingAnchor), body.trailingAnchor.constraint(equalTo: trailingAnchor),
            body.topAnchor.constraint(equalTo: topAnchor), body.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L("Close pin"))
        closeButton.contentTintColor = .white
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closePin)
        closeButton.toolTip = L("Close pin")
        closeButton.identifier = NSUserInterfaceItemIdentifier("close-pin")
        closeButton.setAccessibilityLabel(L("Close pin"))
        restoreButton.image = NSImage(systemSymbolName: "arrow.counterclockwise.circle.fill", accessibilityDescription: L("Restore natural size"))
        restoreButton.contentTintColor = .white
        restoreButton.bezelStyle = .circular
        restoreButton.isBordered = false
        restoreButton.target = self
        restoreButton.action = #selector(restoreSize)
        restoreButton.toolTip = L("Restore natural size")
        restoreButton.identifier = NSUserInterfaceItemIdentifier("restore-pin")
        restoreButton.setAccessibilityLabel(L("Restore natural size"))
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc.fill", accessibilityDescription: L("Copy content"))?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        if let image = copyButton.image {
            image.size = NSSize(width: image.size.width * 13 / image.size.height, height: 13)
        }
        copyButton.contentTintColor = .white
        copyButton.bezelStyle = .circular
        copyButton.isBordered = false
        copyButton.target = self
        copyButton.action = #selector(copyPin)
        copyButton.toolTip = L("Copy content")
        copyButton.identifier = NSUserInterfaceItemIdentifier("copy-pin")
        copyButton.setAccessibilityLabel(L("Copy content"))
        controls.orientation = .horizontal
        controls.spacing = 4
        if filesView == nil { controls.addArrangedSubview(copyButton) }
        controls.addArrangedSubview(restoreButton)
        controls.addArrangedSubview(closeButton)
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.isHidden = true
        controlsBackdrop.translatesAutoresizingMaskIntoConstraints = false
        controlsBackdrop.identifier = NSUserInterfaceItemIdentifier("pin-controls-backdrop")
        controlsBackdrop.isHidden = true
        hoverOutline.translatesAutoresizingMaskIntoConstraints = false
        hoverOutline.identifier = NSUserInterfaceItemIdentifier("pin-hover-outline")
        hoverOutline.isHidden = true
        addSubview(hoverOutline)
        addSubview(controlsBackdrop)
        addSubview(controls)
        NSLayoutConstraint.activate([
            hoverOutline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hoverOutline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hoverOutline.topAnchor.constraint(equalTo: topAnchor),
            hoverOutline.bottomAnchor.constraint(equalTo: bottomAnchor),
            controlsBackdrop.topAnchor.constraint(equalTo: topAnchor),
            controlsBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlsBackdrop.widthAnchor.constraint(equalToConstant: 140),
            controlsBackdrop.heightAnchor.constraint(equalToConstant: 64),
            controls.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            copyButton.widthAnchor.constraint(equalToConstant: 22), copyButton.heightAnchor.constraint(equalToConstant: 22),
            closeButton.widthAnchor.constraint(equalToConstant: 22), closeButton.heightAnchor.constraint(equalToConstant: 22),
            restoreButton.widthAnchor.constraint(equalToConstant: 22), restoreButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func closePin() { onClose?() }
    @objc private func restoreSize() { onRestore?() }
    @objc private func copyPin() { copyContent(to: .general) }

    func copyContent(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if let textEditor { pasteboard.setString(textEditor.string, forType: .string) }
        else if let filesView { pasteboard.writeObjects(filesView.content.urls.map { $0 as NSURL }) }
        else if case .image(let image) = content { pasteboard.writeObjects([image]) }
    }

    func textDidChange(_ notification: Notification) {
        if let textEditor { onTextChange?(textEditor.string) }
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        guard let replacementString else { return true }
        let text = textView.string as NSString
        guard affectedCharRange.location <= text.length,
              affectedCharRange.length <= text.length - affectedCharRange.location else { return false }
        let bytes = textView.string.utf8.count - text.substring(with: affectedCharRange).utf8.count + replacementString.utf8.count
        guard bytes <= ClipboardReader.maximumTextBytes, acceptsTextSize?(bytes) != false else {
            NSSound.beep()
            return false
        }
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        window?.invalidateCursorRects(for: self)
    }

    override func mouseEntered(with event: NSEvent) {
        controlsBackdrop.isHidden = false
        controls.isHidden = false
        hoverOutline.isHidden = usesWindowShadow
        layoutSubtreeIfNeeded()
        window?.invalidateCursorRects(for: self)
    }
    override func mouseExited(with event: NSEvent) {
        controls.isHidden = true
        controlsBackdrop.isHidden = true
        hoverOutline.isHidden = true
        window?.invalidateCursorRects(for: self)
    }

    override func mouseMoved(with event: NSEvent) { updateCursor(with: event) }
    override func cursorUpdate(with event: NSEvent) { updateCursor(with: event) }

    private func updateCursor(with event: NSEvent) {
        resizeCursor(at: convert(event.locationInWindow, from: nil)).set()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if !controls.isHidden {
            for button in [copyButton, closeButton, restoreButton] where button.convert(button.bounds, to: self).contains(local) {
                return button
            }
            if controls.frame.contains(local) { return controls }
        }
        if bounds.contains(local), !edges(at: local).isEmpty || isTextDragMargin(local) { return self }
        return super.hitTest(point)
    }

    func edges(at point: NSPoint) -> ResizeEdges {
        guard bounds.contains(point) else { return [] }
        var result: ResizeEdges = []
        if point.x < Self.resizeInset { result.insert(.left) }
        else if point.x >= bounds.width - Self.resizeInset { result.insert(.right) }
        if point.y < Self.resizeInset { result.insert(.bottom) }
        else if point.y >= bounds.height - Self.resizeInset { result.insert(.top) }
        return result
    }

    func resizeCursor(at point: NSPoint) -> NSCursor {
        if !controls.isHidden, controls.frame.contains(point) { return .arrow }
        let edges = edges(at: point)
        if edges.isEmpty, textEditor != nil {
            return isTextDragMargin(point) ? .openHand : .iBeam
        }
        return cursor(for: edges)
    }

    private func isTextDragMargin(_ point: NSPoint) -> Bool {
        textEditor != nil && point.y >= bounds.height - 12
    }

    private func cursor(for edges: ResizeEdges) -> NSCursor {
        if edges == [.left, .bottom] || edges == [.right, .top] { return Self.diagonalUp }
        if edges == [.left, .top] || edges == [.right, .bottom] { return Self.diagonalDown }
        if !edges.intersection([.left, .right]).isEmpty { return .resizeLeftRight }
        if !edges.intersection([.top, .bottom]).isEmpty { return .resizeUpDown }
        return .arrow
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let d = Self.resizeInset
        addCursorRect(NSRect(x: 0, y: d, width: d, height: max(0, bounds.height - d * 2)), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.width - d, y: d, width: d, height: max(0, bounds.height - d * 2)), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: d, y: 0, width: max(0, bounds.width - d * 2), height: d), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: d, y: bounds.height - d, width: max(0, bounds.width - d * 2), height: d), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: 0, width: d, height: d), cursor: Self.diagonalUp)
        addCursorRect(NSRect(x: bounds.width - d, y: bounds.height - d, width: d, height: d), cursor: Self.diagonalUp)
        addCursorRect(NSRect(x: 0, y: bounds.height - d, width: d, height: d), cursor: Self.diagonalDown)
        addCursorRect(NSRect(x: bounds.width - d, y: 0, width: d, height: d), cursor: Self.diagonalDown)
        if !controls.isHidden {
            for button in [copyButton, closeButton, restoreButton] { addCursorRect(button.convert(button.bounds, to: self), cursor: .arrow) }
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
        let resizeCursor = cursor(for: selectedEdges)
        window.disableCursorRects()
        resizeCursor.push()
        defer {
            NSCursor.pop()
            window.enableCursorRects()
            window.invalidateCursorRects(for: self)
            self.resizeCursor(at: convert(window.mouseLocationOutsideOfEventStream, from: nil)).set()
        }
        // Window coordinates move during left/bottom resizing; deltas use screen coordinates.
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let current = window.convertPoint(toScreen: next.locationInWindow)
            let frame = PinGeometry.resize(frame: initialFrame,
                                           delta: NSPoint(x: current.x - start.x, y: current.y - start.y),
                                           edges: selectedEdges, minimum: window.minSize)
            window.setFrame(frame, display: true)
            resizeCursor.set()
        }
        (window as? PinPanel)?.userDidChangeFrame()
    }
}

private final class PinControlButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let cell = PinControlButtonCell()
        cell.highlightsBy = []
        self.cell = cell
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

private final class PinControlButtonCell: NSButtonCell {
    override func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) {
        let scale: CGFloat = isHighlighted && isEnabled ? 1.16 : 1
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: frame.midX, yBy: frame.midY)
        transform.scale(by: scale)
        transform.translateX(by: -frame.midX, yBy: -frame.midY)
        transform.concat()
        super.drawImage(image, withFrame: frame, in: controlView)
        NSGraphicsContext.restoreGraphicsState()
    }
}

private final class PinHoverOutline: NSView {
    private let stroke = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
        stroke.fillColor = nil
        stroke.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        stroke.lineWidth = 1
        stroke.lineDashPattern = [4, 4]
        stroke.shadowColor = NSColor.black.cgColor
        stroke.shadowOpacity = 0.65
        stroke.shadowRadius = 1
        stroke.shadowOffset = .zero
        layer?.addSublayer(stroke)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stroke.frame = bounds
        stroke.path = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerWidth: 9, cornerHeight: 9, transform: nil)
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class PinControlsBackdrop: NSView {
    private let gradient = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
        gradient.type = .radial
        gradient.colors = [NSColor.black.withAlphaComponent(0.55).cgColor,
                           NSColor.black.withAlphaComponent(0.30).cgColor,
                           NSColor.black.withAlphaComponent(0).cgColor]
        gradient.locations = [0, 0.45, 1]
        gradient.startPoint = CGPoint(x: 0.72, y: 0.72)
        gradient.endPoint = CGPoint(x: 0, y: 0)
        layer?.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class PinImageView: NSView {
    let hasTransparentEdges: Bool

    init(image: NSImage) {
        let bitmap = image.representations.compactMap { ($0 as? NSBitmapImageRep)?.cgImage }.first
            ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        hasTransparentEdges = bitmap.map(PinImageAppearance.hasTransparentEdges(in:)) ?? true
        super.init(frame: .zero)
        wantsLayer = true
        // Use the retained bitmap directly; resolving NSImage at a large point size can upscale it.
        layer?.contents = bitmap
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
        layer?.minificationFilter = .trilinear
        layer?.magnificationFilter = .linear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class PinTextScrollView: NSScrollView {
    override func resetCursorRects() {}

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

private final class PinTextClipView: NSClipView {
    override func resetCursorRects() {}
}

private final class PinTextView: NSTextView {
    override func resetCursorRects() {}

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            window?.performDrag(with: event)
            (window as? PinPanel)?.userDidChangeFrame()
        } else {
            super.mouseDown(with: event)
        }
    }
    override func cursorUpdate(with event: NSEvent) { updatePinCursor(with: event) }
    override func mouseMoved(with event: NSEvent) { updatePinCursor(with: event) }

    private func updatePinCursor(with event: NSEvent) {
        guard let surface = enclosingScrollView?.superview as? PinSurface else { return }
        surface.resizeCursor(at: surface.convert(event.locationInWindow, from: nil)).set()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        textColor = .textColor
    }
}
