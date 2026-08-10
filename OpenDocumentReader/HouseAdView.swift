import StoreKit
import UIKit

/// The promotion for the paid app that takes the banner's place when no ad arrives.
///
/// This is our own content, not an ad: nothing is fetched, no identifier is read and no storage is
/// touched. That is what makes it usable on every no-fill path, including the one where the user
/// refused consent outright and Google is serving limited ads or nothing at all.
///
/// One layout, sized to whatever the slot gives it - the banner height is fixed by the ad slot and
/// cannot grow, so parts drop out instead of wrapping.
final class HouseAdView: UIView {

    /// One rotation of the promotion. `shortHeadline` is what a phone-width slot can actually fit.
    private struct Creative {
        let shortHeadline: String
        let headline: String
        let subline: String
        let callToAction: String
    }

    private static let creatives = [
        Creative(
            shortHeadline: NSLocalizedString(
                "house_ad_support_short", value: "Support us", comment: ""),
            headline: NSLocalizedString(
                "house_ad_support_headline", value: "Support OpenDocument Reader", comment: ""),
            subline: NSLocalizedString(
                "house_ad_support_subline", value: "Get Pro — no ads, ever", comment: ""),
            callToAction: NSLocalizedString(
                "house_ad_cta_go_pro", value: "Go Pro", comment: "")),
        Creative(
            shortHeadline: NSLocalizedString(
                "house_ad_adfree_short", value: "Read without ads", comment: ""),
            headline: NSLocalizedString(
                "house_ad_adfree_headline", value: "Read without ads", comment: ""),
            subline: NSLocalizedString(
                "house_ad_adfree_subline", value: "ODR Pro — a one-time purchase", comment: ""),
            callToAction: NSLocalizedString(
                "house_ad_cta_get_pro", value: "Get Pro", comment: "")),
        Creative(
            shortHeadline: NSLocalizedString(
                "house_ad_source_short", value: "Open source", comment: ""),
            headline: NSLocalizedString(
                "house_ad_source_headline", value: "Open source, kept free", comment: ""),
            subline: NSLocalizedString(
                "house_ad_source_subline", value: "Pro pays for it — and drops the ads", comment: ""),
            callToAction: NSLocalizedString(
                "house_ad_cta_go_pro", value: "Go Pro", comment: "")),
    ]

    /// Round-robin rather than random, so the three are seen evenly and a session does not repeat
    /// the same one. Advanced once per presentation, not once per layout pass.
    private static func nextCreative() -> Creative {
        let defaults = UserDefaults.standard
        let index = defaults.integer(forKey: Constants.key_house_ad_index)

        defaults.set((index + 1) % creatives.count, forKey: Constants.key_house_ad_index)

        return creatives[index % creatives.count]
    }

    // its own imageset rather than the app icon: UIImage(named:) cannot reliably reach an
    // AppIcon.appiconset at runtime
    private let iconView = UIImageView(image: UIImage(named: "house_ad_icon"))
    private lazy var iconWidth = iconView.widthAnchor.constraint(equalToConstant: 34)
    private lazy var iconHeight = iconView.heightAnchor.constraint(equalToConstant: 34)
    private let headlineLabel = UILabel()
    private let sublineLabel = UILabel()
    private let callToActionLabel = PaddedLabel()
    private let textStack = UIStackView()
    private let stack = UIStackView()

    /// What the labels are laid out against until ``rotate()`` picks the one that is actually
    /// shown. Not a rotation itself: taking one here spent a turn on every view that was built,
    /// including the ones in the paid app that never show a promotion at all.
    private var creative = HouseAdView.creatives[0]

    /// Called when the promotion is tapped, so the controller can present the store.
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        setUp()
    }

    private func setUp() {
        backgroundColor = .secondarySystemBackground
        isAccessibilityElement = true
        accessibilityTraits = .button

        iconView.contentMode = .scaleAspectFit
        iconView.layer.cornerRadius = 6
        iconView.clipsToBounds = true
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        headlineLabel.font = .preferredFont(forTextStyle: .footnote).bold()
        headlineLabel.adjustsFontForContentSizeCategory = true
        // truncate rather than wrap: a long translation must shorten, not break the fixed height
        headlineLabel.lineBreakMode = .byTruncatingTail

        sublineLabel.font = .preferredFont(forTextStyle: .caption2)
        sublineLabel.adjustsFontForContentSizeCategory = true
        sublineLabel.textColor = .secondaryLabel
        sublineLabel.lineBreakMode = .byTruncatingTail

        callToActionLabel.font = .preferredFont(forTextStyle: .caption1).bold()
        callToActionLabel.adjustsFontForContentSizeCategory = true
        callToActionLabel.textColor = .systemBackground
        callToActionLabel.backgroundColor = .tintColor
        callToActionLabel.textAlignment = .center
        callToActionLabel.clipsToBounds = true
        callToActionLabel.setContentHuggingPriority(.required, for: .horizontal)
        callToActionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.addArrangedSubview(headlineLabel)
        textStack.addArrangedSubview(sublineLabel)

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 4, leading: 10, bottom: 4, trailing: 10)
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(textStack)
        stack.addArrangedSubview(callToActionLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            iconWidth,
            iconHeight,
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))

        apply(creative)
    }

    /// Picks the next rotation. Called when the promotion is about to be shown, not on every layout
    /// pass, so it does not change under the user while they are looking at it.
    func rotate() {
        creative = HouseAdView.nextCreative()

        apply(creative)
        setNeedsLayout()
    }

    private func apply(_ creative: Creative) {
        sublineLabel.text = creative.subline
        callToActionLabel.text = creative.callToAction

        accessibilityLabel = "\(creative.headline). \(creative.subline)"
        accessibilityHint = creative.callToAction
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = bounds.width
        let isTall = bounds.height >= 70

        // the slot is 50pt on a phone and 90pt on a tablet, and everything here has to fit inside
        // that; each of these is dropped at the width where it stops fitting
        iconView.isHidden = width < 300
        sublineLabel.isHidden = width < 360
        headlineLabel.text = width < 360 ? creative.shortHeadline : creative.headline

        headlineLabel.font =
            isTall ? .preferredFont(forTextStyle: .headline) : .preferredFont(forTextStyle: .footnote).bold()
        sublineLabel.font =
            isTall ? .preferredFont(forTextStyle: .footnote) : .preferredFont(forTextStyle: .caption2)

        // updated, never re-created: activating a fresh pair here would leak one per layout pass
        iconWidth.constant = isTall ? 58 : 34
        iconHeight.constant = isTall ? 58 : 34
        stack.spacing = isTall ? 14 : 10

        callToActionLabel.layer.cornerRadius = callToActionLabel.bounds.height / 2
    }

    @objc private func tapped() {
        onTap?()
    }
}

/// A label with room around its text, for the call-to-action pill.
private final class PaddedLabel: UILabel {

    private let insets = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize

        return CGSize(
            width: size.width + insets.left + insets.right,
            height: size.height + insets.top + insets.bottom)
    }
}

extension UIFont {

    fileprivate func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }

        return UIFont(descriptor: descriptor, size: 0)
    }
}
