import UIKit

/// The document's name as the tool bar shows it.
///
/// A bar item is as wide as what it holds, so a long name would push the
/// buttons off the end. This one truncates instead.
final class DocumentTitleLabel: UILabel {

    /// The most the name may take.
    var maximumWidth: CGFloat = .greatestFiniteMagnitude {
        didSet {
            guard maximumWidth != oldValue else { return }

            invalidateIntrinsicContentSize()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        // the bar sizes it from its intrinsic width, which is what caps it
        translatesAutoresizingMaskIntoConstraints = false

        // the middle of a name says more than its end: "Q3 report (final)" and
        // "Q3 report (draft)" differ where a tail truncation cuts
        lineBreakMode = .byTruncatingMiddle
        textAlignment = .center
        font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .semibold), maximumPointSize: 20)
        adjustsFontForContentSizeCategory = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        capped(super.intrinsicContentSize)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        capped(super.sizeThatFits(size))
    }

    private func capped(_ size: CGSize) -> CGSize {
        CGSize(width: min(size.width, max(0, maximumWidth)), height: size.height)
    }
}
