import AppKit
import PirCore
import OSLog

final class PinPanel: NSPanel, NSWindowDelegate {
    private var userMoveInProgress = false
    private var userMoveTimer: Timer?
    private var programmaticFrameDepth = 0
    override var canBecomeKey: Bool { acceptsKeyboardInput }
    override var canBecomeMain: Bool { false }
    var onClose: (() -> Void)?
    var onFrameChange: ((NSRect) -> Void)?
    var onTextChange: ((String) -> Void)?
    var acceptsTextSize: ((Int) -> Bool)?
    var onFilesChange: ((FilePinContent) -> Void)?
    var onImageScalingChange: ((PinImageScaling) -> Void)?
    var imageScaling: PinImageScaling { (contentView as? PinSurface)?.imageScaling ?? .cover }
    private let naturalSize: NSSize
    private var naturalText: String?
    private var naturalFiles: FilePinContent?
    private let acceptsKeyboardInput: Bool

    init(content: ClipboardContent, screen: NSScreen, offset: Int, restoredFrame: NSRect? = nil, imageScaling: PinImageScaling = .cover) {
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
        let surface = PinSurface(content: content, imageScaling: imageScaling)
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
        surface.onImageScalingChange = { [weak self] mode in self?.onImageScalingChange?(mode) }
        surface.acceptsTextSize = { [weak self] bytes in self?.acceptsTextSize?(bytes) ?? true }
        contentView = surface
        delegate = self
        setAccessibilityLabel(L("Pinned clipboard content"))
        setAccessibilityHelp(L(naturalText == nil ? "Drag to move. Drag any edge to resize. Use the close button to dismiss."
            : "Select and edit text. Drag the top margin to move. Drag any edge to resize."))
    }

    override func close() {
        cancelUserMove()
        (contentView as? PinSurface)?.closeHoverControls()
        super.close()
        onClose?()
        onClose = nil
    }

    func userDidChangeFrame() { onFrameChange?(frame) }

    func setImageScaling(_ mode: PinImageScaling, animated: Bool = true) {
        (contentView as? PinSurface)?.setImageScaling(mode, animated: animated)
    }

    override func performDrag(with event: NSEvent) {
        beginUserMove()
        // WindowServer completes this gesture after performDrag returns, sometimes without mouseUp.
        super.performDrag(with: event)
    }

    private func beginUserMove() {
        guard !userMoveInProgress else { return }
        userMoveInProgress = true
        // A public button-state query also finishes cancelled/zero-distance drags without a delivered mouseUp.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            finishUserMove()
        }
        userMoveTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func finishUserMove() {
        guard userMoveInProgress else { return }
        userDidChangeFrame()
        cancelUserMove()
    }

    private func cancelUserMove() {
        userMoveInProgress = false
        userMoveTimer?.invalidate()
        userMoveTimer = nil
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        (contentView as? PinSurface)?.positionHoverControls()
    }

    func setProgrammaticFrame(_ frameRect: NSRect) {
        cancelUserMove()
        programmaticFrameDepth += 1
        setFrame(frameRect, display: true)
        programmaticFrameDepth -= 1
    }

    func windowWillMove(_ notification: Notification) {
        if programmaticFrameDepth == 0 { beginUserMove() }
    }

    func windowDidMove(_ notification: Notification) {
        (contentView as? PinSurface)?.positionHoverControls()
        guard userMoveInProgress, programmaticFrameDepth == 0 else { return }
        if NSEvent.pressedMouseButtons & 1 == 0 { finishUserMove() }
        else { userDidChangeFrame() }
    }

    func windowDidResize(_ notification: Notification) {
        (contentView as? PinSurface)?.positionHoverControls()
    }

    func capturePendingUserMove() {
        guard userMoveInProgress else { return }
        if NSEvent.pressedMouseButtons & 1 == 0 { finishUserMove() }
        else { userDidChangeFrame() }
    }

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

protocol PinCopyDestination {
    @discardableResult func clearContents() -> Int
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: PinCopyDestination {}

final class PinSurface: NSView, NSTextViewDelegate {
    private(set) var usesWindowShadow = true
    private let closeButton = PinControlButton()
    private let restoreButton = PinControlButton()
    private let copyButton = PinControlButton()
    private let scalingButton = PinControlButton()
    private var imageView: PinImageView?
    private(set) var imageScaling: PinImageScaling
    private var copyFeedbackReset: DispatchWorkItem?
    private(set) var isShowingCopySuccess = false
    private let content: ClipboardContent
    private var textEditor: NSTextView?
    private var filesView: PinFilesView?
    private let controls = NSStackView()
    private let controlsBackdrop = PinControlsBackdrop()
    private var backdropTopConstraint: NSLayoutConstraint?
    private var backdropLeadingConstraint: NSLayoutConstraint?
    private var backdropWidthConstraint: NSLayoutConstraint?
    private var controlsTopConstraint: NSLayoutConstraint?
    private var controlsLeadingConstraint: NSLayoutConstraint?
    private var controlsHorizontalPadding: CGFloat = 8
    private let hoverOutline = PinHoverOutline()
    private let transparentInputRing = CAShapeLayer()
    static let transparentInputAlpha: CGFloat = 1 / 255
    static let resizeInset: CGFloat = 6.5
    private var tracking: NSTrackingArea?
    private var cursorTracking: NSTrackingArea?
    private var activeResizeCursor: NSCursor?
    private var hoverPanel: PinHoverPanel?
    private var hoverHost: PinHoverHost?
    private var isHovered = false
    private var outlineIsVisible = false
    private var hoverGeneration = 0
    private var exitGeneration = 0
    var hoverAnimationDuration: TimeInterval = 0.18
    var onClose: (() -> Void)?
    var onRestore: (() -> Void)?
    var onTextChange: ((String) -> Void)?
    var acceptsTextSize: ((Int) -> Bool)?
    var onFilesChange: ((FilePinContent) -> Void)?
    var onImageScalingChange: ((PinImageScaling) -> Void)?

    init(content: ClipboardContent, imageScaling: PinImageScaling = .cover) {
        self.content = content
        if case .image = content { self.imageScaling = imageScaling }
        else { self.imageScaling = .cover }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true

        let body: NSView
        switch content {
        case .image(let image):
            let imageView = PinImageView(image: image, scaling: imageScaling)
            self.imageView = imageView
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
        if imageView != nil {
            // WindowServer skips zero-alpha pixels, including image fit letterboxing, before NSView hit testing.
            transparentInputRing.fillColor = NSColor.black.withAlphaComponent(Self.transparentInputAlpha).cgColor
            transparentInputRing.fillRule = .evenOdd
            layer?.addSublayer(transparentInputRing)
        }
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
        copyButton.image = copySymbol(success: false)
        copyButton.contentTintColor = .white
        copyButton.bezelStyle = .circular
        copyButton.isBordered = false
        copyButton.target = self
        copyButton.action = #selector(copyPin)
        copyButton.toolTip = L("Copy content")
        copyButton.identifier = NSUserInterfaceItemIdentifier("copy-pin")
        copyButton.setAccessibilityLabel(L("Copy content"))
        scalingButton.contentTintColor = .white
        scalingButton.bezelStyle = .circular
        scalingButton.isBordered = false
        scalingButton.target = self
        scalingButton.action = #selector(toggleImageScaling)
        scalingButton.identifier = NSUserInterfaceItemIdentifier("image-scaling-pin")
        updateScalingButton(animated: false)
        controls.orientation = .horizontal
        controls.spacing = 4
        controls.addArrangedSubview(closeButton)
        controls.addArrangedSubview(restoreButton)
        if imageView != nil { controls.addArrangedSubview(scalingButton) }
        if filesView == nil { controls.addArrangedSubview(copyButton) }
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.isHidden = true
        controlsBackdrop.translatesAutoresizingMaskIntoConstraints = false
        controlsBackdrop.identifier = NSUserInterfaceItemIdentifier("pin-controls-backdrop")
        controlsBackdrop.isHidden = true
        hoverOutline.translatesAutoresizingMaskIntoConstraints = false
        hoverOutline.identifier = NSUserInterfaceItemIdentifier("pin-hover-outline")
        hoverOutline.isHidden = true
        addSubview(hoverOutline)
        controlsBackdrop.setUniformFill(imageView != nil)
        let controlsParent: NSView
        if usesWindowShadow {
            controlsParent = self
        } else {
            let host = PinHoverHost(frame: NSRect(x: 0, y: 0, width: controlsWidth, height: 40))
            host.onEnter = { [weak self] in self?.setHovered(true) }
            host.onExit = { [weak self] in self?.scheduleHoverExit() }
            hoverHost = host
            controlsParent = host
        }
        controlsParent.addSubview(controlsBackdrop)
        controlsParent.addSubview(controls)
        let backdropTop = controlsBackdrop.topAnchor.constraint(equalTo: controlsParent.topAnchor)
        let backdropLeading = controlsBackdrop.leadingAnchor.constraint(equalTo: controlsParent.leadingAnchor)
        let backdropWidth = controlsBackdrop.widthAnchor.constraint(equalToConstant: imageView == nil ? 140 : controlsWidth)
        let controlsTop = controls.topAnchor.constraint(equalTo: controlsParent.topAnchor, constant: 8)
        let controlsLeading = controls.leadingAnchor.constraint(equalTo: controlsParent.leadingAnchor, constant: 8)
        backdropTopConstraint = backdropTop
        backdropLeadingConstraint = backdropLeading
        backdropWidthConstraint = backdropWidth
        controlsTopConstraint = controlsTop
        controlsLeadingConstraint = controlsLeading
        NSLayoutConstraint.activate([
            hoverOutline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hoverOutline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hoverOutline.topAnchor.constraint(equalTo: topAnchor),
            hoverOutline.bottomAnchor.constraint(equalTo: bottomAnchor),
            backdropTop, backdropLeading, backdropWidth,
            controlsBackdrop.heightAnchor.constraint(equalToConstant: imageView == nil ? 64 : 40),
            controlsTop, controlsLeading,
            copyButton.widthAnchor.constraint(equalToConstant: 22), copyButton.heightAnchor.constraint(equalToConstant: 22),
            scalingButton.widthAnchor.constraint(equalToConstant: 22), scalingButton.heightAnchor.constraint(equalToConstant: 22),
            closeButton.widthAnchor.constraint(equalToConstant: 22), closeButton.heightAnchor.constraint(equalToConstant: 22),
            restoreButton.widthAnchor.constraint(equalToConstant: 22), restoreButton.heightAnchor.constraint(equalToConstant: 22)
        ])
        updateControlsLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func closePin() { onClose?() }
    @objc private func restoreSize() { onRestore?() }
    @objc private func copyPin() { copyContent(to: NSPasteboard.general) }

    @discardableResult
    func copyContent(to pasteboard: PinCopyDestination) -> Bool {
        pasteboard.clearContents()
        let succeeded: Bool
        if let textEditor { succeeded = pasteboard.setString(textEditor.string, forType: .string) }
        else if let filesView { succeeded = pasteboard.writeObjects(filesView.content.urls.map { $0 as NSURL }) }
        else if case .image(let image) = content { succeeded = pasteboard.writeObjects([image]) }
        else { succeeded = false }
        if filesView == nil { setCopyFeedback(succeeded) }
        return succeeded
    }

    private func copySymbol(success: Bool) -> NSImage? {
        let symbol = success ? "checkmark" : "doc.on.doc.fill"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: L(success ? "Copied" : "Copy content"))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        if let image { image.size = NSSize(width: image.size.width * 13 / image.size.height, height: 13) }
        return image
    }

    private func setCopyFeedback(_ succeeded: Bool) {
        copyFeedbackReset?.cancel()
        copyFeedbackReset = nil
        isShowingCopySuccess = succeeded
        copyButton.setImage(copySymbol(success: succeeded), animated: true)
        copyButton.setAccessibilityValue(succeeded ? L("Copied") : nil)
        guard succeeded else { return }
        let reset = DispatchWorkItem { [weak self] in
            guard let self else { return }
            isShowingCopySuccess = false
            copyButton.setImage(copySymbol(success: false), animated: true)
            copyButton.setAccessibilityValue(nil)
            copyFeedbackReset = nil
        }
        copyFeedbackReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: reset)
    }

    @objc private func toggleImageScaling() {
        setImageScaling(imageScaling == .cover ? .fit : .cover)
    }

    func setImageScaling(_ mode: PinImageScaling, animated: Bool = true) {
        guard let imageView, imageScaling != mode else { return }
        imageScaling = mode
        imageView.setScaling(mode, animated: animated)
        updateScalingButton(animated: animated)
        refreshHoverOutline(animated: animated)
        onImageScalingChange?(mode)
    }

    private func updateScalingButton(animated: Bool) {
        let fit = imageScaling == .cover
        let label = L(fit ? "Fit entire image" : "Fill image frame")
        let image = NSImage(systemSymbolName: fit ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                            accessibilityDescription: label)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        scalingButton.setImage(image, animated: animated)
        scalingButton.toolTip = label
        scalingButton.setAccessibilityLabel(label)
    }

    private var controlsWidth: CGFloat {
        CGFloat(controls.arrangedSubviews.count) * 22 + CGFloat(max(0, controls.arrangedSubviews.count - 1)) * controls.spacing + controlsHorizontalPadding * 2
    }

    private func updateControlsLayout() {
        guard imageView != nil, usesWindowShadow else { return }
        let compact = bounds.width > 0 && bounds.width < 132
        let padding: CGFloat = compact ? 4 : 8
        let spacing: CGFloat = compact ? 2 : 4
        if controls.spacing != spacing { controls.spacing = spacing }
        controlsHorizontalPadding = padding
        let values: [(NSLayoutConstraint?, CGFloat)] = [(backdropTopConstraint, 8), (backdropLeadingConstraint, 8),
            (backdropWidthConstraint, controlsWidth), (controlsTopConstraint, 16), (controlsLeadingConstraint, 8 + padding)]
        for (constraint, value) in values {
            if let constraint, constraint.constant != value { constraint.constant = value }
        }
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
        if let cursorTracking { removeTrackingArea(cursorTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        // AppKit suppresses cursorUpdate for activeAlways areas, so cursor requests use a separate activation policy.
        let cursorArea = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(cursorArea)
        cursorTracking = cursorArea
        window?.invalidateCursorRects(for: self)
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
        updateCursor(with: event)
    }
    override func mouseExited(with event: NSEvent) {
        if let activeResizeCursor { activeResizeCursor.set() }
        else { NSCursor.arrow.set() }
        if hoverHost == nil { setHovered(false) }
        else { scheduleHoverExit() }
    }

    private func scheduleHoverExit() {
        exitGeneration += 1
        let generation = exitGeneration
        // The small gap between content and its child controls remains traversable during exit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self, generation == exitGeneration else { return }
            let mouse = NSEvent.mouseLocation
            if window?.frame.contains(mouse) == true || hoverPanel?.frame.contains(mouse) == true { return }
            setHovered(false)
        }
    }

    func setHovered(_ hovered: Bool) {
        exitGeneration += 1
        guard isHovered != hovered else { return }
        layoutSubtreeIfNeeded()
        isHovered = hovered
        hoverGeneration += 1
        let generation = hoverGeneration
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : hoverAnimationDuration
        if hovered {
            positionHoverControls()
            hoverPanel?.alphaValue = 1
            hoverPanel?.ignoresMouseEvents = false
            if window?.isVisible == true { hoverPanel?.orderFrontRegardless() }
        }
        let animated = [controlsBackdrop, controls]
        for view in animated {
            animateHover(view, visible: hovered, zoom: !usesWindowShadow && view !== controlsBackdrop, duration: duration)
        }
        refreshHoverOutline(animated: true)
        if !hovered {
            if duration == 0 { hideHoverPanel() }
            else {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                    guard let self, generation == hoverGeneration, !isHovered else { return }
                    hideHoverPanel()
                }
            }
        }
        window?.invalidateCursorRects(for: self)
    }

    private func refreshHoverOutline(animated: Bool) {
        guard let imageView else { return }
        let hasVisibleBounds = imageView.hasTransparentEdges || (imageScaling == .fit && imageView.hasLetterboxing(in: bounds.size))
        let visible = isHovered && hasVisibleBounds
        guard outlineIsVisible != visible else { return }
        outlineIsVisible = visible
        let duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? hoverAnimationDuration : 0
        animateHover(hoverOutline, visible: visible, zoom: !usesWindowShadow, duration: duration)
    }

    private func hideHoverPanel() {
        hoverPanel?.alphaValue = 0
        hoverPanel?.ignoresMouseEvents = true
    }

    private func hoverTransform(for view: NSView, scale: CGFloat) -> CATransform3D {
        let shift = CATransform3DMakeTranslation(view.bounds.midX * (1 - scale), view.bounds.midY * (1 - scale), 0)
        return CATransform3DScale(shift, scale, scale, 1)
    }

    private func animateHover(_ view: NSView, visible: Bool, zoom: Bool, duration: TimeInterval) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let fromOpacity = view.isHidden ? Float(0) : layer.presentation()?.opacity ?? layer.opacity
        let transformLayer = (view as? PinHoverOutline)?.contentLayer ?? layer
        let maximumDimension = max(1, max(view.bounds.width, view.bounds.height))
        let hiddenScale: CGFloat = view is PinHoverOutline ? max(0.92, 1 - 4 / maximumDimension) : 0.92
        let fromTransform = view.isHidden ? hoverTransform(for: view, scale: hiddenScale) : transformLayer.presentation()?.transform ?? transformLayer.transform
        layer.removeAnimation(forKey: "pin-hover")
        transformLayer.removeAnimation(forKey: "pin-hover-zoom")
        view.isHidden = false
        let targetOpacity: Float = visible ? 1 : 0
        let targetTransform = hoverTransform(for: view, scale: visible || !zoom ? 1 : hiddenScale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = targetOpacity
        transformLayer.transform = targetTransform
        CATransaction.commit()
        guard duration > 0 else { view.isHidden = !visible; return }
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = fromOpacity
        opacity.toValue = targetOpacity
        var animations: [CAAnimation] = [opacity]
        if zoom {
            let transform = CABasicAnimation(keyPath: "transform")
            transform.fromValue = NSValue(caTransform3D: fromTransform)
            transform.toValue = NSValue(caTransform3D: targetTransform)
            if transformLayer === layer { animations.append(transform) }
            else {
                transform.duration = duration
                transform.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                transformLayer.add(transform, forKey: "pin-hover-zoom")
            }
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(group, forKey: "pin-hover")
        if !visible {
            let generation = hoverGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak view] in
                guard let self, generation == hoverGeneration, view?.layer?.opacity == 0 else { return }
                view?.isHidden = true
            }
        }
    }

    func positionHoverControls() {
        guard let host = hoverHost, let window else { return }
        if hoverPanel == nil {
            let panel = PinHoverPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
            panel.contentView = host
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.addChildWindow(panel, ordered: .above)
            hoverPanel = panel
        }
        guard let panel = hoverPanel else { return }
        let visible = window.screen?.visibleFrame ?? window.frame
        let above = window.frame.maxY + 2
        let y = above + 40 <= visible.maxY ? above : max(visible.minY, window.frame.minY - 42)
        panel.setFrame(NSRect(x: min(max(window.frame.minX, visible.minX), visible.maxX - controlsWidth), y: y, width: controlsWidth, height: 40), display: true)
        host.layoutSubtreeIfNeeded()
    }

    func closeHoverControls() {
        copyFeedbackReset?.cancel()
        copyFeedbackReset = nil
        exitGeneration += 1
        hoverGeneration += 1
        if let hoverPanel {
            window?.removeChildWindow(hoverPanel)
            hoverPanel.close()
        }
        hoverPanel = nil
    }

    override func layout() {
        updateControlsLayout()
        super.layout()
        guard imageView != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        transparentInputRing.frame = bounds
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(bounds.insetBy(dx: Self.resizeInset, dy: Self.resizeInset))
        transparentInputRing.path = path
        CATransaction.commit()
        refreshHoverOutline(animated: false)
    }

    override func mouseMoved(with event: NSEvent) { updateCursor(with: event) }
    override func cursorUpdate(with event: NSEvent) { updateCursor(with: event) }

    private func updateCursor(with event: NSEvent) {
        (activeResizeCursor ?? resizeCursor(at: convert(event.locationInWindow, from: nil))).set()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateControlsLayout()
        refreshHoverOutline(animated: false)
        window?.invalidateCursorRects(for: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if isHovered, hoverHost == nil {
            for button in controls.arrangedSubviews.compactMap({ $0 as? NSButton }) where button.convert(button.bounds, to: self).contains(local) {
                return button
            }
            if controls.frame.contains(local) { return controls }
            if imageView != nil, controlsBackdrop.frame.contains(local) { return self }
        }
        if bounds.contains(local), !edges(at: local).isEmpty || isTextDragMargin(local) || isFileDragMargin(local) { return self }
        return super.hitTest(point)
    }

    func edges(at point: NSPoint) -> ResizeEdges {
        guard bounds.contains(point) else { return [] }
        var result: ResizeEdges = []
        if point.x < bounds.minX + Self.resizeInset { result.insert(.left) }
        else if point.x >= bounds.maxX - Self.resizeInset { result.insert(.right) }
        if point.y < bounds.minY + Self.resizeInset { result.insert(.bottom) }
        else if point.y >= bounds.maxY - Self.resizeInset { result.insert(.top) }
        return result
    }

    func resizeCursor(at point: NSPoint) -> NSCursor {
        if isHovered, hoverHost == nil,
           controls.frame.contains(point) || (imageView != nil && controlsBackdrop.frame.contains(point)) { return .arrow }
        let edges = edges(at: point)
        if edges.isEmpty, textEditor != nil {
            return isTextDragMargin(point) ? .openHand : .iBeam
        }
        return cursor(for: edges)
    }

    private func isTextDragMargin(_ point: NSPoint) -> Bool {
        textEditor != nil && point.y >= bounds.height - 12
    }

    private func isFileDragMargin(_ point: NSPoint) -> Bool {
        filesView.map { $0.isDragArea(at: $0.convert(point, from: self)) } ?? false
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
        if isHovered, hoverHost == nil {
            if imageView != nil { addCursorRect(controlsBackdrop.frame, cursor: .arrow) }
            for button in controls.arrangedSubviews.compactMap({ $0 as? NSButton }) { addCursorRect(button.convert(button.bounds, to: self), cursor: .arrow) }
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
            return
        }
        let initialFrame = window.frame
        let start = window.convertPoint(toScreen: event.locationInWindow)
        let resizeCursor = cursor(for: selectedEdges)
        activeResizeCursor = resizeCursor
        window.disableCursorRects()
        resizeCursor.push()
        defer {
            activeResizeCursor = nil
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

private final class PinHoverPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PinHoverHost: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { NSCursor.arrow.set(); onEnter?() }
    override func mouseMoved(with event: NSEvent) { NSCursor.arrow.set() }
    override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

private final class PinControlButton: NSButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let cell = PinControlButtonCell()
        cell.highlightsBy = []
        self.cell = cell
    }

    func setImage(_ image: NSImage?, animated: Bool) {
        wantsLayer = true
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            displayIfNeeded()
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.18
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(transition, forKey: "pin-symbol")
        } else { layer?.removeAnimation(forKey: "pin-symbol") }
        self.image = image
        needsDisplay = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

private final class PinControlButtonCell: NSButtonCell {
    private var tintSource: NSImage?
    private var whiteSymbol: NSImage?

    override func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) {
        // NSButtonCell derives highlighted template images differently across macOS releases.
        let source = self.image ?? image
        guard source.size.width > 0, source.size.height > 0 else { return }
        if tintSource !== source {
            tintSource = source
            whiteSymbol = NSImage(size: source.size, flipped: false) { rect in
                source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                            respectFlipped: true, hints: nil)
                NSColor.white.setFill()
                rect.fill(using: .sourceIn)
                return true
            }
        }
        let scale: CGFloat = isHighlighted && isEnabled ? 1.16 : 1
        let available = controlView.bounds.insetBy(dx: 2, dy: 2).size
        let fit = min(1, min(available.width / source.size.width, available.height / source.size.height))
        let size = NSSize(width: source.size.width * fit * scale, height: source.size.height * fit * scale)
        let drawingFrame = NSRect(x: controlView.bounds.midX - size.width / 2,
                                  y: controlView.bounds.midY - size.height / 2, width: size.width, height: size.height)
        whiteSymbol?.draw(in: drawingFrame, from: .zero, operation: .sourceOver,
                          fraction: isEnabled ? 1 : 0.5, respectFlipped: true,
                          hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }
}

private final class PinHoverOutline: NSView {
    let contentLayer = CALayer()
    private let contrastContainer = CALayer()
    private let contrast = CAShapeLayer()
    private let outsideMask = CAShapeLayer()
    private let stroke = CAShapeLayer()
    private let edgeMask = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
        contrast.name = "pin-hover-outline-contrast"
        contrast.fillColor = nil
        contrast.strokeColor = NSColor.black.withAlphaComponent(0.5).cgColor
        contrast.lineWidth = 2.5
        contrast.lineDashPattern = [4, 4]
        contrast.shadowColor = NSColor.black.cgColor
        contrast.shadowOpacity = 0.25
        contrast.shadowRadius = 0.6
        contrast.shadowOffset = .zero
        stroke.name = "pin-hover-outline-stroke"
        stroke.fillColor = nil
        stroke.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        stroke.lineWidth = 1
        stroke.lineDashPattern = [4, 4]
        edgeMask.fillRule = .evenOdd
        edgeMask.fillColor = NSColor.black.cgColor
        contentLayer.name = "pin-hover-outline-content"
        contentLayer.anchorPoint = .zero
        contrastContainer.name = "pin-hover-outline-contrast-container"
        outsideMask.fillRule = .evenOdd
        outsideMask.fillColor = NSColor.black.cgColor
        contrastContainer.addSublayer(contrast)
        contrastContainer.mask = outsideMask
        contentLayer.addSublayer(contrastContainer)
        contentLayer.addSublayer(stroke)
        layer?.addSublayer(contentLayer)
        // The mask stays stationary while the stroke zooms, retaining the existing resize input perimeter.
        layer?.mask = edgeMask
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.bounds = bounds
        contentLayer.position = bounds.origin
        // Half-point alignment gives the one-point white stroke a complete pixel at 1x scale.
        let outline = CGPath(roundedRect: bounds.insetBy(dx: 2.5, dy: 2.5), cornerWidth: 9, cornerHeight: 9, transform: nil)
        contrastContainer.frame = bounds
        for line in [contrast, stroke] {
            line.frame = bounds
            line.path = outline
        }
        // Clip the composited dark stroke and its shadow outside the white stroke's outer boundary.
        outsideMask.frame = bounds
        let outside = CGMutablePath()
        outside.addRect(bounds)
        outside.addPath(CGPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), cornerWidth: 9.5, cornerHeight: 9.5, transform: nil))
        outsideMask.path = outside
        edgeMask.frame = bounds
        let inputBounds = CGMutablePath()
        inputBounds.addRect(bounds)
        inputBounds.addRect(bounds.insetBy(dx: PinSurface.resizeInset, dy: PinSurface.resizeInset))
        edgeMask.path = inputBounds
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
        gradient.startPoint = CGPoint(x: 0.28, y: 0.72)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.addSublayer(gradient)
    }

    func setUniformFill(_ uniform: Bool) {
        if uniform { gradient.removeFromSuperlayer() }
        else if gradient.superlayer == nil { layer?.addSublayer(gradient) }
        layer?.backgroundColor = uniform ? NSColor.black.withAlphaComponent(0.5).cgColor : nil
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
    let imageLayer = CALayer()
    private let imageSize: NSSize
    private var scaling: PinImageScaling
    private var layoutSize: NSSize?

    init(image: NSImage, scaling: PinImageScaling = .cover) {
        imageSize = image.size
        self.scaling = scaling
        let bitmap = image.representations.compactMap { ($0 as? NSBitmapImageRep)?.cgImage }.first
            ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        hasTransparentEdges = bitmap.map(PinImageAppearance.hasTransparentEdges(in:)) ?? true
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        // The bitmap remains unchanged while its image rectangle interpolates inside the clipping view.
        imageLayer.name = "pin-image-content"
        imageLayer.anchorPoint = .zero
        imageLayer.contents = bitmap
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        imageLayer.magnificationFilter = .linear
        layer?.addSublayer(imageLayer)
    }

    func hasLetterboxing(in size: NSSize) -> Bool {
        guard imageSize.width > 0, imageSize.height > 0, size.width > 0, size.height > 0 else { return false }
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        return size.width - imageSize.width * scale > 0.5 || size.height - imageSize.height * scale > 0.5
    }

    override func layout() {
        super.layout()
        guard layoutSize != bounds.size else { return }
        updateImageGeometry(animated: false)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard layoutSize != bounds.size else { return }
        updateImageGeometry(animated: false)
    }

    func setScaling(_ scaling: PinImageScaling, animated: Bool) {
        superview?.layoutSubtreeIfNeeded()
        self.scaling = scaling
        updateImageGeometry(animated: animated)
    }

    private func updateImageGeometry(animated: Bool) {
        layoutSize = bounds.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let horizontal = bounds.width / imageSize.width
        let vertical = bounds.height / imageSize.height
        let scale = scaling == .cover ? max(horizontal, vertical) : min(horizontal, vertical)
        let targetSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let targetBounds = NSRect(origin: .zero, size: targetSize)
        let targetPosition = NSPoint(x: bounds.midX - targetSize.width / 2, y: bounds.midY - targetSize.height / 2)
        let presented = imageLayer.presentation()
        let previousBounds = presented?.bounds ?? imageLayer.bounds
        let previousPosition = presented?.position ?? imageLayer.position
        imageLayer.removeAnimation(forKey: "pin-image-scaling")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.bounds = targetBounds
        imageLayer.position = targetPosition
        CATransaction.commit()
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              previousBounds != targetBounds || previousPosition != targetPosition else { return }
        let sizeAnimation = CABasicAnimation(keyPath: "bounds")
        sizeAnimation.fromValue = NSValue(rect: previousBounds)
        sizeAnimation.toValue = NSValue(rect: targetBounds)
        let positionAnimation = CABasicAnimation(keyPath: "position")
        positionAnimation.fromValue = NSValue(point: previousPosition)
        positionAnimation.toValue = NSValue(point: targetPosition)
        let group = CAAnimationGroup()
        group.animations = [sizeAnimation, positionAnimation]
        group.duration = 0.24
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        imageLayer.add(group, forKey: "pin-image-scaling")
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
