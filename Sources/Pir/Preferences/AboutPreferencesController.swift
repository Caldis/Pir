import AppKit

final class AboutPreferencesController: PreferencesPageController {
    private let model: PreferencesModel
    private let artwork = AboutBrandArtwork(frame: .zero)

    init(model: PreferencesModel) {
        self.model = model
        super.init(page: .about)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func loadView() {
        super.loadView()
        let name = PreferencesStyle.label("Pir", font: .systemFont(ofSize: 70, weight: .ultraLight))
        let version = PreferencesStyle.label(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
                                             font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        let copyright = PreferencesStyle.label("© 2026 Caldis", font: .systemFont(ofSize: 9), color: .secondaryLabelColor)
        let tagline = PreferencesStyle.label(L("Keep a thought in sight."), font: .systemFont(ofSize: 11, weight: .light))
        let website = button(L("Homepage"), tag: 0)
        let source = button("Github", tag: 1)
        let welcome = button(L("Welcome to Pir"), tag: 2)
        let license = button(L("License"), tag: 3)
        let donate = button(L("Feed the cat"), tag: 4)
        let links = NSStackView(views: [website, source, welcome])
        links.orientation = .horizontal
        links.spacing = 8
        links.alignment = .centerY
        artwork.translatesAutoresizingMaskIntoConstraints = false
        links.translatesAutoresizingMaskIntoConstraints = false
        for child in [artwork, name, version, copyright, tagline, links, license, donate] { view.addSubview(child) }
        NSLayoutConstraint.activate([
            artwork.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            artwork.topAnchor.constraint(equalTo: view.topAnchor),
            artwork.heightAnchor.constraint(equalToConstant: 77),
            name.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PreferencesStyle.margin),
            name.topAnchor.constraint(equalTo: view.topAnchor),
            name.widthAnchor.constraint(equalToConstant: 120),
            name.heightAnchor.constraint(equalToConstant: 83),
            version.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 10),
            version.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            copyright.leadingAnchor.constraint(equalTo: version.leadingAnchor),
            copyright.topAnchor.constraint(equalTo: version.bottomAnchor, constant: 5),
            tagline.leadingAnchor.constraint(equalTo: version.leadingAnchor),
            tagline.topAnchor.constraint(equalTo: copyright.bottomAnchor, constant: 5),
            tagline.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -PreferencesStyle.margin),
            links.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PreferencesStyle.margin),
            links.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PreferencesStyle.margin),
            links.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 8),
            website.widthAnchor.constraint(equalToConstant: 120),
            source.widthAnchor.constraint(equalToConstant: 80),
            welcome.widthAnchor.constraint(equalTo: links.widthAnchor, constant: -216),
            license.leadingAnchor.constraint(equalTo: links.leadingAnchor),
            license.widthAnchor.constraint(equalTo: website.widthAnchor),
            license.topAnchor.constraint(equalTo: links.bottomAnchor, constant: 14),
            donate.leadingAnchor.constraint(equalTo: license.trailingAnchor, constant: 8),
            donate.trailingAnchor.constraint(equalTo: links.trailingAnchor),
            donate.centerYAnchor.constraint(equalTo: license.centerYAnchor)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        artwork.setPresentationActive(true)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        artwork.setPresentationActive(false)
    }

    private func button(_ title: String, tag: Int) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(openDestination(_:)))
        button.tag = tag
        button.bezelStyle = .roundRect
        button.font = .systemFont(ofSize: 12, weight: .light)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return button
    }

    @objc private func openDestination(_ sender: NSButton) {
        let destination: String
        switch sender.tag {
        case 0: destination = "https://pir.caldis.me/"
        case 1: destination = "https://github.com/Caldis/Pir"
        case 2: model.onShowOnboarding?(); return
        case 3: destination = "https://github.com/Caldis/Pir/blob/main/LICENSE"
        case 4:
            present(DonationController(), asPopoverRelativeTo: sender.bounds, of: sender,
                    preferredEdge: .maxX, behavior: .transient)
            return
        default: return
        }
        if let url = URL(string: destination) { NSWorkspace.shared.open(url) }
    }
}
