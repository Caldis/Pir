import AppKit
import Combine

final class UpdatesPreferencesController: PreferencesPageController {
    private let updates: UpdateManager
    private let check = NSButton(title: L("Check Now"), target: nil, action: nil)
    private let onStart = NSButton(checkboxWithTitle: L("Check on app start"), target: nil, action: nil)
    private let beta = NSButton(checkboxWithTitle: L("Including beta version"), target: nil, action: nil)
    private var observations: Set<AnyCancellable> = []

    init(updates: UpdateManager? = nil) {
        self.updates = updates ?? .shared
        super.init(page: .updates)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func loadView() {
        super.loadView()
        let title = PreferencesStyle.label(L("Check for updates"), font: PreferencesStyle.labelFont,
                                           color: .secondaryLabelColor)
        title.alignment = .right
        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info["CFBundleVersion"] as? String ?? "—"
        let version = PreferencesStyle.label("\(L("Current Version")): \(shortVersion) · \(build)",
                                             font: .systemFont(ofSize: 10, weight: .light), color: .secondaryLabelColor)
        check.bezelStyle = .roundRect
        check.font = .systemFont(ofSize: 12, weight: .light)
        check.target = self
        check.action = #selector(checkNow)
        for button in [onStart, beta] {
            button.controlSize = .small
            button.font = PreferencesStyle.labelFont
            button.target = self
        }
        onStart.action = #selector(changeStartupCheck)
        beta.action = #selector(changeBetaChannel)
        for child in [title, check, version, onStart, beta] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PreferencesStyle.margin),
            title.widthAnchor.constraint(equalToConstant: PreferencesStyle.labelWidth),
            title.topAnchor.constraint(equalTo: check.topAnchor, constant: -1),
            check.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: PreferencesStyle.columnSpacing),
            check.topAnchor.constraint(equalTo: view.topAnchor, constant: PreferencesStyle.margin),
            check.widthAnchor.constraint(equalToConstant: 130),
            check.heightAnchor.constraint(equalToConstant: 18),
            version.leadingAnchor.constraint(equalTo: check.leadingAnchor),
            version.topAnchor.constraint(equalTo: check.bottomAnchor, constant: 6),
            version.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PreferencesStyle.margin),
            onStart.leadingAnchor.constraint(equalTo: check.leadingAnchor),
            onStart.topAnchor.constraint(equalTo: version.bottomAnchor, constant: 8),
            onStart.heightAnchor.constraint(equalToConstant: PreferencesStyle.checkboxHeight),
            beta.leadingAnchor.constraint(equalTo: check.leadingAnchor),
            beta.topAnchor.constraint(equalTo: onStart.bottomAnchor, constant: 6),
            beta.heightAnchor.constraint(equalToConstant: PreferencesStyle.checkboxHeight)
        ])
        updates.$canCheckForUpdates.receive(on: RunLoop.main).sink { [weak self] in self?.check.isEnabled = $0 }
            .store(in: &observations)
        updates.preferences.$checkOnAppStart.receive(on: RunLoop.main).sink { [weak self] in self?.onStart.state = $0 ? .on : .off }
            .store(in: &observations)
        updates.preferences.$includingBetaVersion.receive(on: RunLoop.main).sink { [weak self] in self?.beta.state = $0 ? .on : .off }
            .store(in: &observations)
    }

    @objc private func checkNow() { updates.checkForUpdates() }
    @objc private func changeStartupCheck() { updates.preferences.checkOnAppStart = onStart.state == .on }
    @objc private func changeBetaChannel() { updates.preferences.includingBetaVersion = beta.state == .on }
}
