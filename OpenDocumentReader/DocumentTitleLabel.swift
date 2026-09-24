import UIKit

/// The document's name as the tool bar shows it.
final class DocumentTitleLabel: UILabel {

    override init(frame: CGRect) {
        super.init(frame: frame)

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
}
