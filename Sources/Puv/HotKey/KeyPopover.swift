// Adapted from Caldis/Mos (752730c); Puv copy relicensed by Caldis under the repository LICENSE.
// Keyboard-only adaptation for Puv; see THIRD_PARTY_NOTICES.md.
import Cocoa

class KeyPopover: NSObject, NSPopoverDelegate {
    var onClose: (() -> Void)?
    func popoverDidClose(_ notification: Notification) { onClose?() }
    private enum RecordingHint {
        case escape
        case duplicate

        var localizedText: String {
            switch self {
            case .escape:
                return L("Press Escape to cancel")
            case .duplicate:
                return L("Shortcut unavailable. Try another combination.")
            }
        }
    }

    private var popover: NSPopover?
    var keyPreview: KeyPreview!
    private var hintLabel: NSTextField?
    private var hintHeightConstraint: NSLayoutConstraint?
    private var hintBottomConstraint: NSLayoutConstraint?
    private var contentView: NSView?

    private let baseHeight: CGFloat = 45
    private let hintHeight: CGFloat = 18
    private let hiddenHintBottomPadding: CGFloat = 10
    private let visibleHintBottomPadding: CGFloat = 5

    func show(at sourceView: NSView) {
        hide()
        setupPopover()
        popover?.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
    }

    func hide() {
        popover?.close()
        popover = nil
    }

    func showEscHint() {
        showHint(.escape)
    }

    func showDuplicateHint() {
        showHint(.duplicate)
    }

    private func showHint(_ hint: RecordingHint) {
        guard let label = hintLabel,
              let heightConstraint = hintHeightConstraint else { return }

        label.stringValue = hint.localizedText
        hintBottomConstraint?.constant = -visibleHintBottomPadding
        guard heightConstraint.constant == 0 else { return }

        guard popover?.isShown == true else {
            label.alphaValue = 1
            heightConstraint.constant = hintHeight
            updatePopoverContentSize()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.allowsImplicitAnimation = true
            label.animator().alphaValue = 1
            heightConstraint.animator().constant = hintHeight
        }, completionHandler: { [weak self] in
            self?.updatePopoverContentSize()
        })
    }



    private func updatePopoverContentSize() {
        contentView?.layout()
        if let size = contentView?.fittingSize {
            popover?.contentSize = size
        }
    }

    private func getContentView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        contentView = view

        keyPreview = KeyPreview()
        keyPreview.translatesAutoresizingMaskIntoConstraints = false
        let hintLabel = NSTextField(labelWithString: RecordingHint.escape.localizedText)
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = NSColor.secondaryLabelColor
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.alphaValue = 0
        hintLabel.setContentHuggingPriority(.required, for: .vertical)
        self.hintLabel = hintLabel

        let heightConstraint = hintLabel.heightAnchor.constraint(equalToConstant: 0)
        hintHeightConstraint = heightConstraint
        let bottomConstraint = hintLabel.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: -hiddenHintBottomPadding
        )
        hintBottomConstraint = bottomConstraint

        view.addSubview(keyPreview)
        view.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            keyPreview.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            keyPreview.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),

            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: keyPreview.bottomAnchor, constant: 4),
            bottomConstraint,
            heightConstraint,

            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 165),
        ])

        return view
    }

    private func setupPopover() {
        let newPopover = NSPopover()
        newPopover.contentViewController = NSViewController()
        newPopover.contentViewController?.view = getContentView()
        newPopover.behavior = .semitransient
        newPopover.delegate = self
        popover = newPopover
    }
}
