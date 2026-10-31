import StoreKit
import UIKit

/// Offers the yearly pass, with the Pro app beside it for a single payment. Lite only. From the
/// gate, `featureMessage` says what the user just tried; nil from every other way in.
final class PassViewController: UIViewController {

    /// What the user just tried, from the gate. Also the name analytics reports it under.
    struct Feature {
        let name: String
        let message: String
    }

    private let feature: Feature?

    /// After the sheet is gone: open the Pro app on the App Store.
    var onGetPro: (() -> Void)?

    private let subscribeButton = UIButton(type: .system)
    private let restoreButton = UIButton(type: .system)

    init(feature: Feature?) {
        self.feature = feature

        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .pageSheet
        sheetPresentationController?.detents = [.medium(), .large()]
        sheetPresentationController?.prefersGrabberVisible = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Shows the sheet over `host`, and reports it the way OpenDocument.droid does.
    static func present(from host: UIViewController, feature: Feature?, onGetPro: @escaping () -> Void) {
        if let feature {
            AnalyticsManager.shared.report("pro_gate_shown", parameters: ["feature": feature.name])
        } else {
            AnalyticsManager.shared.report("pass_shown")
        }

        let sheet = PassViewController(feature: feature)
        sheet.onGetPro = onGetPro

        host.present(sheet, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        let titleLabel = label(
            NSLocalizedString(feature == nil ? "pass_title" : "pro_feature_title", comment: ""),
            font: .preferredFont(forTextStyle: .title2).bold, color: .label)
        titleLabel.accessibilityTraits = .header

        var subscribe = UIButton.Configuration.filled()
        subscribe.title = NSLocalizedString("pass_buy_no_price", comment: "")
        subscribe.buttonSize = .large
        subscribeButton.configuration = subscribe
        subscribeButton.addTarget(self, action: #selector(subscribeTapped), for: .touchUpInside)

        var pro = UIButton.Configuration.bordered()
        pro.title = NSLocalizedString("pass_get_pro", comment: "")
        pro.buttonSize = .large
        let proButton = UIButton(configuration: pro)
        proButton.addTarget(self, action: #selector(getProTapped), for: .touchUpInside)

        var notNow = UIButton.Configuration.plain()
        notNow.title = NSLocalizedString("not_now", comment: "")
        let notNowButton = UIButton(configuration: notNow)
        notNowButton.addTarget(self, action: #selector(notNowTapped), for: .touchUpInside)

        // the App Store asks for these next to a subscription
        restoreButton.configuration = smallLink(NSLocalizedString("pass_restore", comment: ""))
        restoreButton.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)
        let termsButton = UIButton(configuration: smallLink(NSLocalizedString("pass_terms_of_use", comment: "")))
        termsButton.addTarget(self, action: #selector(termsTapped), for: .touchUpInside)
        let privacyButton = UIButton(configuration: smallLink(NSLocalizedString("pass_privacy_policy", comment: "")))
        privacyButton.addTarget(self, action: #selector(privacyTapped), for: .touchUpInside)

        let links = UIStackView(arrangedSubviews: [restoreButton, termsButton, privacyButton])
        links.axis = .horizontal
        links.distribution = .equalCentering

        var rows: [UIView] = [titleLabel]
        if let feature {
            rows.append(label(feature.message, font: .preferredFont(forTextStyle: .body), color: .label))
        }
        rows += [
            label(
                NSLocalizedString("pass_why", comment: ""), font: .preferredFont(forTextStyle: .body),
                color: .secondaryLabel),
            subscribeButton,
            label(
                NSLocalizedString("pass_terms", comment: ""), font: .preferredFont(forTextStyle: .footnote),
                color: .secondaryLabel, centered: true),
            proButton,
            notNowButton,
            links,
        ]

        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(4, after: subscribeButton)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24),
        ])

        // the button is up from the start, and shows the price once the App Store gives one
        Task { [weak self] in
            guard let product = await Pass.shared.loadProduct(), let self else { return }

            self.subscribeButton.configuration?.title = String(
                format: NSLocalizedString("pass_buy", comment: ""), product.displayPrice)
        }
    }

    private func label(_ text: String, font: UIFont, color: UIColor, centered: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = centered ? .center : .natural

        return label
    }

    private func smallLink(_ title: String) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.buttonSize = .mini
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .preferredFont(forTextStyle: .caption1)

            return attributes
        }

        return configuration
    }

    // MARK: - actions

    private func reportGateTapped() {
        // the gate's purchase, under the name OpenDocument.droid reports it
        if let feature {
            AnalyticsManager.shared.report("pro_gate_tapped", parameters: ["feature": feature.name])
        }
    }

    @objc private func subscribeTapped() {
        AnalyticsManager.shared.report("pass_tapped", parameters: ["feature": feature?.name ?? "none"])
        reportGateTapped()

        subscribeButton.configuration?.showsActivityIndicator = true
        subscribeButton.isEnabled = false

        Task { [weak self] in
            let outcome = await Pass.shared.purchase()

            guard let self else { return }

            self.subscribeButton.configuration?.showsActivityIndicator = false
            self.subscribeButton.isEnabled = true

            switch outcome {
            case .unlocked:
                // the screen below says thank you, see Pass.didUnlock
                self.dismiss(animated: true)
            case .notNow:
                break
            case .unavailable:
                self.say(NSLocalizedString("pass_unavailable", comment: ""))
            }
        }
    }

    @objc private func getProTapped() {
        reportGateTapped()

        let onGetPro = self.onGetPro
        dismiss(animated: true) {
            onGetPro?()
        }
    }

    @objc private func notNowTapped() {
        dismiss(animated: true)
    }

    @objc private func restoreTapped() {
        AnalyticsManager.shared.report("pass_restore_tapped")

        restoreButton.isEnabled = false

        Task { [weak self] in
            let restored = await Pass.shared.restore()

            guard let self else { return }

            self.restoreButton.isEnabled = true

            if restored {
                // the screen below says that the purchase is restored, see Pass.didUnlock
                self.dismiss(animated: true)
            } else {
                self.say(NSLocalizedString("pass_nothing_to_restore", comment: ""))
            }
        }
    }

    @objc private func termsTapped() {
        open("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    }

    @objc private func privacyTapped() {
        open("https://opendocument.app/privacy")
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }

        UIApplication.shared.open(url)
    }

    private func say(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("ok", comment: ""), style: .default))

        present(alert, animated: true)
    }
}

extension UIFont {
    fileprivate var bold: UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }

        return UIFont(descriptor: descriptor, size: 0)
    }
}
