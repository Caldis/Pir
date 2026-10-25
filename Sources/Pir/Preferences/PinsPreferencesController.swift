import AppKit
import SwiftUI

final class PinsPreferencesController: PreferencesPageController {
    private let hosting: NSHostingController<PinsPreferencesView>

    init(model: PreferencesModel) {
        hosting = NSHostingController(rootView: PinsPreferencesView(manager: model.pins))
        super.init(page: .pins)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func loadView() {
        super.loadView()
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

struct PinsPreferencesView: View {
    @ObservedObject var manager: PinManager
    private enum PendingAlert: String, Identifiable {
        case clear, limit
        var id: String { rawValue }
    }
    @State private var pendingAlert: PendingAlert?

    var body: some View {
        VStack(spacing: 0) {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            if !manager.summaries.isEmpty {
                Divider()
                HStack {
                    Spacer()
                    Button(L("Clear all")) { pendingAlert = .clear }
                        .controlSize(.small)
                }.padding(.horizontal, 20).padding(.vertical, 10)
            }
        }
        .alert(item: $pendingAlert) { alert in
            switch alert {
            case .clear:
                return Alert(title: Text(L("Clear all pins")),
                             message: Text(L("All pins and saved content, including hidden pins, will be deleted.")),
                             primaryButton: .destructive(Text(L("Clear all"))) { manager.deleteAll() },
                             secondaryButton: .cancel(Text(L("Cancel"))))
            case .limit:
                return Alert(title: Text(L("Close a pin before adding another.")))
            }
        }
    }

    private var content: some View {
        Group {
            if manager.summaries.isEmpty {
                VStack(spacing: 10) {
                    Image(nsImage: Self.emptyArtwork).renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 96, height: 78).foregroundStyle(.secondary)
                    Text(L("No pins yet")).font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                    Text(L("Copy something, then press your shortcut."))
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }.offset(y: -10).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(manager.summaries) { pin in
                            pinRow(pin)
                            if pin.id != manager.summaries.last?.id { Divider().padding(.leading, 52) }
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 8)
                }
            }
        }
    }

    private static let emptyArtwork: NSImage = {
        let image = Bundle.module.url(forResource: "EmptyPins", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
            ?? NSImage(size: NSSize(width: 126, height: 96))
        image.isTemplate = true
        return image
    }()

    private func pinRow(_ pin: PinSummary) -> some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail = pin.thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                } else {
                    Image(systemName: pin.kind == .image ? "photo" : pin.kind == .files ? "folder" : "text.alignleft")
                        .font(.system(size: 17)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.quaternary.opacity(0.45))
                }
            }.frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if pin.kind == .image {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(pin.title).lineLimit(1).foregroundStyle(pin.isHidden ? .secondary : .primary)
                Text(L(pin.kind == .image ? "Image" : pin.kind == .files ? "Files" : "Text"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Button(L("Paste")) {
                do { try manager.pasteAgain(pin.id) }
                catch { pendingAlert = .limit }
            }
            .controlSize(.small)
            .help(L("Paste again"))
            .accessibilityLabel(L("Paste again"))
            Button {
                manager.setHidden(!pin.isHidden, for: pin.id)
            } label: {
                Image(systemName: pin.isHidden ? "eye.slash" : "eye")
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.borderless)
            .help(L(pin.isHidden ? "Show pin" : "Hide pin"))
            .accessibilityLabel(L(pin.isHidden ? "Show pin" : "Hide pin"))
            Button(role: .destructive) { manager.delete(pin.id) } label: {
                Image(systemName: "trash").frame(width: 24, height: 28)
            }
            .buttonStyle(.borderless).help(L("Delete pin")).accessibilityLabel(L("Delete pin"))
        }.padding(.vertical, 9)
    }
}

