import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import PuvCore
import OSLog
import Combine

struct PinSummary: Identifiable {
    let id: UUID
    let kind: PinRecord.Kind
    let title: String
    let createdAt: Date
    var isHidden: Bool
    var thumbnail: NSImage?
}

final class PinManager: ObservableObject {
    private struct LivePin {
        let panel: PinPanel
        let content: ClipboardContent
        var record: PinRecord
        let bytes: Int
        var presentedFrame: NSRect
        var summary: PinSummary
    }
    private enum RestoredContent {
        case text(String)
        case image(CGImage, NSSize)
    }
    private var pins: [UUID: LivePin] = [:]
    private var estimatedBytes = 0
    private let logger = Logger(subsystem: "me.caldis.puv", category: "pins")
    private let store: PinSessionStorage
    private let io = DispatchQueue(label: "me.caldis.puv.session", qos: .utility)
    private let previews = DispatchQueue(label: "me.caldis.puv.previews", qos: .utility)
    @Published private(set) var summaries: [PinSummary] = []
    private var pendingSave: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var restorationStarted = false
    private var restorationFinished = false
    // Accessed on the I/O queue, then consumed on main only after an I/O barrier.
    private var restored: [(PinRecord, RestoredContent)] = []
    private var persistenceErrorShown = false
    var onPersistenceFailure: (() -> Void)?
    static let maximumPins = 32
    static let maximumBytes = 256 * 1024 * 1024

    init(store: PinSessionStorage = PinSessionStore()) {
        self.store = store
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.reconcileDisplays()
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        pendingSave?.cancel()
    }

    func restoreSession() {
        guard !restorationStarted else { return }
        restorationStarted = true
        io.async { [weak self] in
            guard let self else { return }
            do {
                let records = try self.store.load()
                var decodedBytes = 0
                for item in records {
                    guard self.restored.count < Self.maximumPins else { break }
                    switch item.record.kind {
                    case .text:
                        guard let text = String(data: item.data, encoding: .utf8), !text.isEmpty else { continue }
                        let bytes = text.utf8.count * 6
                        guard decodedBytes + bytes <= Self.maximumBytes else { continue }
                        decodedBytes += bytes
                        self.restored.append((item.record, .text(text)))
                    case .image:
                        guard let source = CGImageSourceCreateWithData(item.data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                              let width = properties[kCGImagePropertyPixelWidth] as? Int,
                              let height = properties[kCGImagePropertyPixelHeight] as? Int,
                              width > 0, height > 0, width <= ClipboardReader.maximumImageDimension, height <= ClipboardReader.maximumImageDimension,
                              decodedBytes + width * height * 4 <= Self.maximumBytes,
                              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { continue }
                        let size = item.record.imagePointSize ?? NSSize(width: width, height: height)
                        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { continue }
                        decodedBytes += width * height * 4
                        self.restored.append((item.record, .image(image, size)))
                    }
                }
            } catch { self.reportPersistenceFailure() }
            DispatchQueue.main.async { [weak self] in self?.finishRestoration() }
        }
    }

    private func finishRestoration() {
        guard !restorationFinished else { return }
        // restoreSession's worker has completed before this barrier returns, including during termination.
        io.sync {}
        restorationFinished = true
        let snapshot = io.sync { () -> [(PinRecord, RestoredContent)] in
            defer { restored.removeAll() }
            return restored
        }
        let topology = displays()
        for (record, savedContent) in snapshot {
            guard let placement = record.anchor.resolve(displays: topology, fallbackDisplayID: primaryDisplayID()),
                  let screen = screen(with: placement.displayID) else { continue }
            let content: ClipboardContent
            switch savedContent {
            case .text(let text): content = .text(text)
            case .image(let image, let size):
                let representation = NSBitmapImageRep(cgImage: image)
                representation.size = size
                let value = NSImage(size: size)
                value.addRepresentation(representation)
                content = .image(value)
            }
            let bytes = byteCost(content)
            guard pins.count < Self.maximumPins, estimatedBytes + bytes <= Self.maximumBytes else { continue }
            let panel = PinPanel(content: content, screen: screen, offset: pins.count, restoredFrame: placement.frame)
            register(panel: panel, record: record, bytes: bytes, content: content)
        }
        scheduleSave()
        logger.info("Session restored count=\(self.pins.count, privacy: .public)")
    }

    @discardableResult
    func show(_ content: ClipboardContent, on preferredScreen: NSScreen? = nil) throws -> UUID? {
        if restorationStarted, !restorationFinished { finishRestoration() }
        let bytes = byteCost(content)
        guard pins.count < Self.maximumPins, estimatedBytes + bytes <= Self.maximumBytes else { throw PinError.limit }
        guard let screen = preferredScreen ?? NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main,
              let display = display(screen) else { return nil }
        let id = UUID()
        let panel = PinPanel(content: content, screen: screen, offset: pins.count)
        let kind: PinRecord.Kind
        var imageSize: NSSize?
        switch content {
        case .image(let image): kind = .image; imageSize = image.size
        case .text: kind = .text
        }
        let record = PinRecord(id: id, kind: kind, anchor: PinAnchor(frame: panel.frame, display: display), imagePointSize: imageSize)
        register(panel: panel, record: record, bytes: bytes, content: content)
        persistContent(content, id: id)
        if !restorationStarted { restorationStarted = true; restorationFinished = true }
        scheduleSave()
        logger.info("Pin created kind=\(kind.rawValue, privacy: .public) count=\(self.pins.count, privacy: .public)")
        return id
    }

    @discardableResult
    func reveal(_ id: UUID) -> Bool {
        guard let pin = pins[id] else { return false }
        setHidden(false, for: id)
        pin.panel.orderFrontRegardless()
        return true
    }

    private func register(panel: PinPanel, record: PinRecord, bytes: Int, content: ClipboardContent) {
        let id = record.id
        panel.onClose = { [weak self] in
            guard let self, let removed = self.pins.removeValue(forKey: id) else { return }
            self.estimatedBytes -= removed.bytes
            self.publishSummaries()
            self.io.async {
                do { try self.store.remove(id) }
                catch { self.reportPersistenceFailure() }
            }
            self.scheduleSave(immediately: true)
            self.logger.info("Pin closed count=\(self.pins.count, privacy: .public)")
        }
        // Only completed user gestures change ownership. AppKit/programmatic topology moves never overwrite the preferred display.
        panel.onFrameChange = { [weak self] frame in
            guard let self, var pin = self.pins[id] else { return }
            pin.record.anchor = pin.record.anchor.updatedByUser(frame: frame, previousFrame: pin.presentedFrame, displays: self.displays())
            pin.presentedFrame = frame
            self.pins[id] = pin
            self.scheduleSave()
        }
        let title: String
        switch content {
        case .text(let text):
            let first = text.prefix(180).prefix { !$0.isNewline }.trimmingCharacters(in: .whitespaces)
            title = first.isEmpty ? L("Text") : first
        case .image(let image):
            title = String(format: "%.0f × %.0f pt", image.size.width, image.size.height)
        }
        let summary = PinSummary(id: id, kind: record.kind, title: title, createdAt: record.createdAt,
                                 isHidden: record.isHidden, thumbnail: nil)
        pins[id] = LivePin(panel: panel, content: content, record: record, bytes: bytes, presentedFrame: panel.frame, summary: summary)
        estimatedBytes += bytes
        if !record.isHidden { panel.orderFrontRegardless() }
        publishSummaries()
        if case .image(let image) = content { makeThumbnail(for: id, image: image) }
    }

    func setHidden(_ hidden: Bool, for id: UUID) {
        guard var pin = pins[id], pin.record.isHidden != hidden else { return }
        pin.record.isHidden = hidden
        pin.summary.isHidden = hidden
        if hidden { pin.panel.orderOut(nil) }
        else { pin.panel.orderFrontRegardless() }
        pins[id] = pin
        publishSummaries()
        scheduleSave(immediately: true)
    }

    func delete(_ id: UUID) { pins[id]?.panel.close() }

    func pasteAgain(_ id: UUID) throws {
        if restorationStarted, !restorationFinished { finishRestoration() }
        guard let pin = pins[id] else { return }
        try show(pin.content)
    }

    func deleteAll() {
        if restorationStarted, !restorationFinished { finishRestoration() }
        for id in Array(pins.keys) { delete(id) }
    }

    private func publishSummaries() {
        summaries = pins.values.map(\.summary).sorted { $0.createdAt < $1.createdAt }
    }

    private func makeThumbnail(for id: UUID, image: NSImage) {
        guard let bitmap = retainedBitmap(image) else { return }
        previews.async { [weak self] in
            guard let context = CGContext(data: nil, width: 96, height: 96, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            let scale = max(96 / CGFloat(bitmap.width), 96 / CGFloat(bitmap.height))
            let size = CGSize(width: CGFloat(bitmap.width) * scale, height: CGFloat(bitmap.height) * scale)
            context.interpolationQuality = .medium
            context.draw(bitmap, in: CGRect(x: (96 - size.width) / 2, y: (96 - size.height) / 2,
                                            width: size.width, height: size.height))
            guard let thumbnail = context.makeImage() else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, var pin = self.pins[id] else { return }
                let representation = NSBitmapImageRep(cgImage: thumbnail)
                representation.size = NSSize(width: 48, height: 48)
                let preview = NSImage(size: representation.size)
                preview.addRepresentation(representation)
                pin.summary.thumbnail = preview
                self.pins[id] = pin
                self.publishSummaries()
            }
        }
    }

    private func retainedBitmap(_ image: NSImage) -> CGImage? {
        image.representations.compactMap { ($0 as? NSBitmapImageRep)?.cgImage }.first
            ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func persistContent(_ content: ClipboardContent, id: UUID) {
        switch content {
        case .text(let text):
            io.async { [weak self] in
                guard let self else { return }
                do { try self.store.writeContent(Data(text.utf8), for: id) }
                catch { self.reportPersistenceFailure() }
            }
        case .image(let image):
            // CGImage is immutable; snapshot AppKit state on main, then encode pixels off the UI thread once.
            guard let bitmap = retainedBitmap(image) else { reportPersistenceFailure(); return }
            io.async { [weak self] in
                guard let self else { return }
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
                    self.reportPersistenceFailure(); return
                }
                CGImageDestinationAddImage(destination, bitmap, nil)
                guard CGImageDestinationFinalize(destination) else { self.reportPersistenceFailure(); return }
                do { try self.store.writeContent(data as Data, for: id) }
                catch { self.reportPersistenceFailure() }
            }
        }
    }

    private func scheduleSave(immediately: Bool = false) {
        guard restorationFinished else { return }
        pendingSave?.cancel()
        let records = pins.values.map(\.record)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.io.async {
                // A partial recovery cannot establish deletion; only an explicit close removes assets.
                do { try self.store.save(records, removingMissing: false) }
                catch { self.reportPersistenceFailure() }
            }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediately ? 0 : 0.4), execute: work)
    }

    func flushSession() {
        if restorationStarted, !restorationFinished { finishRestoration() }
        pendingSave?.cancel()
        let records = pins.values.map(\.record)
        io.sync {
            do { try store.save(records, removingMissing: false) }
            catch { reportPersistenceFailure() }
        }
    }

    func closeAll() {
        let existing = pins.values.map(\.panel)
        pins.removeAll()
        estimatedBytes = 0
        publishSummaries()
        for panel in existing { panel.onClose = nil; panel.close() }
    }

    private func reconcileDisplays() {
        let topology = displays()
        for (id, var pin) in pins {
            guard let placement = pin.record.anchor.resolve(displays: topology, fallbackDisplayID: primaryDisplayID()) else { continue }
            pin.panel.setFrame(placement.frame, display: true)
            pin.presentedFrame = pin.panel.frame
            pins[id] = pin
        }
    }

    private func byteCost(_ content: ClipboardContent) -> Int {
        switch content {
        case .text(let text): return text.utf8.count * 6
        case .image(let image):
            return image.representations.map { max(0, $0.pixelsWide) * max(0, $0.pixelsHigh) * 4 }.max() ?? Int(image.size.width * image.size.height) * 4
        }
    }

    private func displays() -> [PinDisplay] { NSScreen.screens.compactMap(display) }
    private func screen(with id: String) -> NSScreen? { NSScreen.screens.first { display($0)?.id == id } }
    private func primaryDisplayID() -> String? {
        let main = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        }
        return main.flatMap(display)?.id
    }
    private func display(_ screen: NSScreen) -> PinDisplay? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return PinDisplay(id: CFUUIDCreateString(nil, uuid) as String, visibleFrame: screen.visibleFrame)
    }

    private func reportPersistenceFailure() {
        logger.error("Session storage operation failed")
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.persistenceErrorShown else { return }
            self.persistenceErrorShown = true
            self.onPersistenceFailure?()
        }
    }
    enum PinError: Error { case limit }
}
