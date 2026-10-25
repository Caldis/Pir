import AppKit

final class DonationController: NSViewController {
    override func loadView() {
        preferredContentSize = NSSize(width: 705, height: 691)
        view = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))

        let catLink = actionButton(L("How fat is the cat ?"), tag: 0)
        catLink.bezelStyle = .regularSquare
        catLink.setButtonType(.momentaryPushIn)
        catLink.identifier = NSUserInterfaceItemIdentifier("donation-cat-link")
        let horizontalRule = separator()
        let verticalRule = separator()
        let payments = NSView()
        payments.translatesAutoresizingMaskIntoConstraints = false
        payments.identifier = NSUserInterfaceItemIdentifier("donation-payments")
        let photo = image("Meow", suffix: "jpeg", label: L("Feed the cat"))
        photo.imageScaling = .scaleProportionallyUpOrDown
        photo.identifier = NSUserInterfaceItemIdentifier("donation-photo")

        for child in [catLink, horizontalRule, payments, verticalRule, photo] { view.addSubview(child) }
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: preferredContentSize.width),
            view.heightAnchor.constraint(equalToConstant: preferredContentSize.height),
            catLink.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            catLink.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            catLink.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            catLink.heightAnchor.constraint(equalToConstant: 32),
            horizontalRule.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            horizontalRule.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            horizontalRule.topAnchor.constraint(equalTo: catLink.bottomAnchor, constant: 20),
            horizontalRule.heightAnchor.constraint(equalToConstant: 1),
            payments.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            payments.topAnchor.constraint(equalTo: horizontalRule.bottomAnchor),
            payments.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            payments.widthAnchor.constraint(equalToConstant: 240),
            verticalRule.leadingAnchor.constraint(equalTo: payments.trailingAnchor),
            verticalRule.topAnchor.constraint(equalTo: payments.topAnchor),
            verticalRule.bottomAnchor.constraint(equalTo: payments.bottomAnchor),
            verticalRule.widthAnchor.constraint(equalToConstant: 1),
            photo.leadingAnchor.constraint(equalTo: verticalRule.trailingAnchor),
            photo.widthAnchor.constraint(equalToConstant: 464),
            photo.heightAnchor.constraint(equalToConstant: 618),
            photo.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            photo.topAnchor.constraint(equalTo: payments.topAnchor),
            photo.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let wechatLogo = themedImage(light: "WeChatPayForLight", dark: "WeChatPayForDark", label: L("WeChat Pay"))
        let wechatQR = themedImage(light: "WeChatPayQRForLight", dark: "WeChatPayQRForDark", label: L("WeChat Pay"))
        let alipayLogo = themedImage(light: "AliPayForLight", dark: "AliPayForDark", label: L("Alipay"))
        let alipayQR = themedImage(light: "AliPayQRForLight", dark: "AliPayQRForDark", label: L("Alipay"))
        let paypalLogo = themedImage(light: "PayPalForLight", dark: "PayPalForDark", darkSuffix: "pdf", label: "PayPal")
        let paypal = actionButton(L("Donate via PayPal"), tag: 1)
        let coffeeLogo = image("bmc-brand-logo", suffix: "svg", label: "Buy me a coffee")
        let coffee = actionButton(L("Buy me a coffee"), tag: 2)
        wechatQR.alphaValue = 0.8
        alipayQR.alphaValue = 0.8

        let rows: [(NSView, CGFloat, CGFloat, CGFloat)] = [
            (wechatLogo, 100, 33, 30), (wechatQR, 150, 110, 10),
            (alipayLogo, 100, 35, 30), (alipayQR, 150, 110, 10),
            (paypalLogo, 100, 40, 30), (paypal, 132, 24, 13),
            (coffeeLogo, 140, 40, 30), (coffee, 132, 24, 13)
        ]
        var previous: NSView?
        for (child, width, height, spacing) in rows {
            payments.addSubview(child)
            NSLayoutConstraint.activate([
                child.centerXAnchor.constraint(equalTo: payments.centerXAnchor),
                child.widthAnchor.constraint(equalToConstant: width),
                child.heightAnchor.constraint(equalToConstant: height),
                child.topAnchor.constraint(equalTo: previous?.bottomAnchor ?? payments.topAnchor, constant: spacing)
            ])
            previous = child
        }
    }

    override func cancelOperation(_ sender: Any?) { dismiss(nil) }

    private func separator() -> NSBox {
        let rule = NSBox()
        rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        return rule
    }

    private func image(_ name: String, suffix: String, label: String) -> NSImageView {
        let image = DonationFixedImageView()
        image.image = DonationImageView.resource(name, suffix: suffix)
        image.imageScaling = .scaleProportionallyDown
        image.imageAlignment = .alignLeft
        image.setAccessibilityLabel(label)
        image.translatesAutoresizingMaskIntoConstraints = false
        return image
    }

    private func themedImage(light: String, dark: String, darkSuffix: String = "png", label: String) -> NSImageView {
        let image = DonationImageView(light: light, dark: dark, darkSuffix: darkSuffix)
        image.imageScaling = .scaleProportionallyDown
        image.imageAlignment = .alignLeft
        image.setAccessibilityLabel(label)
        image.translatesAutoresizingMaskIntoConstraints = false
        return image
    }

    private func actionButton(_ title: String, tag: Int) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(activate(_:)))
        button.tag = tag
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    @objc private func activate(_ sender: NSButton) {
        let destination: String
        switch sender.tag {
        case 0:
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
            destination = "https://meow.caldis.me?from=PuvApplication&version=\(version)"
        case 1: destination = "https://www.paypal.me/mosapp"
        case 2: destination = "https://buymeacoffee.com/caldis"
        default: return
        }
        if let url = URL(string: destination) { NSWorkspace.shared.open(url) }
    }
}

private class DonationFixedImageView: NSImageView {
    // Source image pixel dimensions are independent of the popover's point layout.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

private final class DonationImageView: DonationFixedImageView {
    private let lightImage: NSImage?
    private let darkImage: NSImage?

    init(light: String, dark: String, darkSuffix: String) {
        lightImage = Self.resource(light, suffix: "png")
        darkImage = Self.resource(dark, suffix: darkSuffix)
        super.init(frame: .zero)
        refreshImage()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshImage()
    }

    private func refreshImage() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        image = dark ? darkImage : lightImage
    }

    static func resource(_ name: String, suffix: String) -> NSImage? {
        Bundle.module.url(forResource: name, withExtension: suffix).flatMap(NSImage.init(contentsOf:))
    }
}
