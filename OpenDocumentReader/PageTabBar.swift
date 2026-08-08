import UIKit

/// A horizontally scrollable row of text tabs, one per document page.
///
/// Replaces the vendored ScrollableSegmentedControl, whose upstream was archived
/// in 2022, and covers only what the document view asked of it: text tabs that
/// share the available width while they fit, scroll once they do not, and
/// underline the selected one.
final class PageTabBar: UIControl {
    static let titlePadding: CGFloat = 8
    static let underlineHeight: CGFloat = 4
    static let titleTextStyle = UIFont.TextStyle.subheadline

    /// What the tabs took before they scaled with the text size.
    private static let minimumHeight: CGFloat = 40

    /// Tall enough not to clip the title at the current text size — the familiar
    /// 40 points by default, growing from there.
    var preferredHeight: CGFloat {
        let lineHeight = UIFont.preferredFont(forTextStyle: Self.titleTextStyle, compatibleWith: traitCollection)
            .lineHeight

        return max((lineHeight + Self.titlePadding * 2 + Self.underlineHeight).rounded(.up), Self.minimumHeight)
    }

    /// The tab titles, in order. Setting this clears the selection.
    var titles: [String] = [] {
        didSet {
            selection = nil

            measureTitles()
            reload()
            setNeedsLayout()
        }
    }

    /// Following `UISegmentedControl`, setting this does not send
    /// `.valueChanged` — only a tap does.
    var selectedIndex: Int? {
        get { selection }
        set { select(newValue, notify: false) }
    }

    private var selection: Int?
    private var titleWidths: [CGFloat] = []
    private var tabWidths: [CGFloat] = []
    private var laidOutSize: CGSize = .zero

    private let layout = UICollectionViewFlowLayout()
    private lazy var collectionView = UICollectionView(frame: bounds, collectionViewLayout: layout)

    override init(frame: CGRect) {
        super.init(frame: frame)

        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configure()
    }

    private func configure() {
        clipsToBounds = true

        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0

        collectionView.frame = bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(TabCell.self, forCellWithReuseIdentifier: TabCell.reuseIdentifier)
        addSubview(collectionView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // tab widths depend on how much room there is. only on an actual change,
        // or the invalidation would bounce back here forever
        guard bounds.size != laidOutSize else { return }

        laidOutSize = bounds.size
        resizeTabs()
        layout.invalidateLayout()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory
        else {
            return
        }

        measureTitles()
        reload()
        setNeedsLayout()
    }

    private func measureTitles() {
        let font = UIFont.preferredFont(forTextStyle: Self.titleTextStyle, compatibleWith: traitCollection)
        let attributes = [NSAttributedString.Key.font: font]

        titleWidths = titles.map {
            (($0 as NSString).size(withAttributes: attributes).width + Self.titlePadding * 2).rounded(.up)
        }

        resizeTabs()
    }

    /// Every tab gets an even share of the row while that is wide enough for the
    /// longest title. Failing that they keep their own widths and share out
    /// whatever is left over, so a single long sheet name is neither truncated
    /// nor allowed to dictate the width of the short ones.
    private func resizeTabs() {
        guard let widestTitle = titleWidths.max() else {
            tabWidths = []

            return
        }

        let evenWidth = bounds.width / CGFloat(titleWidths.count)

        if widestTitle <= evenWidth {
            tabWidths = titleWidths.map { _ in evenWidth }

            return
        }

        let slack = bounds.width - titleWidths.reduce(0, +)

        tabWidths =
            slack > 0
            ? titleWidths.map { $0 + slack / CGFloat(titleWidths.count) }
            : titleWidths
    }

    private func select(_ index: Int?, notify: Bool) {
        let index = index.flatMap { titles.indices.contains($0) ? $0 : nil }

        guard index != selection else { return }

        selection = index
        showSelection(animated: true)

        if notify {
            sendActions(for: .valueChanged)
        }
    }

    private func reload() {
        collectionView.reloadData()
        showSelection(animated: false)
    }

    private func showSelection(animated: Bool) {
        guard let selection else {
            collectionView.indexPathsForSelectedItems?.forEach {
                collectionView.deselectItem(at: $0, animated: animated)
            }

            return
        }

        collectionView.selectItem(
            at: IndexPath(item: selection, section: 0),
            animated: animated,
            scrollPosition: .centeredHorizontally
        )
    }
}

extension PageTabBar: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        titles.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
    {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TabCell.reuseIdentifier, for: indexPath)

        (cell as? TabCell)?.title = titles[indexPath.item]

        return cell
    }
}

extension PageTabBar: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        select(indexPath.item, notify: true)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        CGSize(width: tabWidths[indexPath.item], height: collectionView.bounds.height)
    }
}

private final class TabCell: UICollectionViewCell {
    static let reuseIdentifier = "PageTabBar.TabCell"

    private let titleLabel = UILabel()
    private let underline = UIView()

    var title: String? {
        get { titleLabel.text }
        set {
            titleLabel.text = newValue
            accessibilityLabel = newValue
        }
    }

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    override var isHighlighted: Bool {
        didSet { updateAppearance() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configure()
    }

    private func configure() {
        isAccessibilityElement = true

        titleLabel.font = .preferredFont(forTextStyle: PageTabBar.titleTextStyle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        underline.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(underline)

        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: PageTabBar.titlePadding),
            titleLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -PageTabBar.titlePadding),

            underline.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            underline.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            underline.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            underline.heightAnchor.constraint(equalToConstant: PageTabBar.underlineHeight),
        ])

        updateAppearance()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()

        updateAppearance()
    }

    private func updateAppearance() {
        let active = isSelected || isHighlighted

        titleLabel.textColor = active ? .label : .secondaryLabel
        underline.backgroundColor = tintColor
        underline.isHidden = !active

        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}
