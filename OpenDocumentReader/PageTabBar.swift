import UIKit

/// A horizontally scrollable row of text tabs, one per document page.
///
/// This is what the document view uses to switch between the pages or sheets of
/// a document. It replaces the vendored ScrollableSegmentedControl, whose
/// upstream was archived in 2022, and covers only what the document view asked
/// of it: equal-width text tabs that share the available width while they fit,
/// scroll once they do not, and underline the selected one.
final class PageTabBar: UIControl {
    fileprivate static let titlePadding: CGFloat = 8
    fileprivate static let underlineHeight: CGFloat = 4
    fileprivate static let titleTextStyle = UIFont.TextStyle.subheadline

    /// The tab titles, in order. Setting this clears the selection.
    var titles: [String] = [] {
        didSet {
            selection = nil

            measureTitles()
            reload()
            setNeedsLayout()
        }
    }

    /// The selected tab, or nil when nothing is selected.
    ///
    /// Following `UISegmentedControl`, setting this does not send
    /// `.valueChanged` — only a tap does.
    var selectedIndex: Int? {
        get { selection }
        set { select(newValue, notify: false) }
    }

    private var selection: Int?
    private var titleWidths: [CGFloat] = []
    private var laidOutSize: CGSize = .zero

    private let layout = UICollectionViewFlowLayout()
    private lazy var collectionView = UICollectionView(frame: bounds, collectionViewLayout: layout)

    /// The width every tab gets while they all fit, or nil once the row has to
    /// scroll and each tab is only as wide as its own title.
    private var sharedTabWidth: CGFloat? {
        guard !titles.isEmpty, titleWidths.reduce(0, +) <= bounds.width else { return nil }

        return bounds.width / CGFloat(titles.count)
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

        // Tab widths depend on how much room there is, so a resize has to go
        // through the flow layout again. Only on an actual change, or the
        // invalidation would bounce back here forever.
        guard bounds.size != laidOutSize else { return }

        laidOutSize = bounds.size
        layout.invalidateLayout()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory else {
            return
        }

        measureTitles()
        reload()
        setNeedsLayout()
    }

    private func measureTitles() {
        let attributes = [NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: Self.titleTextStyle)]

        titleWidths = titles.map {
            (($0 as NSString).size(withAttributes: attributes).width + Self.titlePadding * 2).rounded(.up)
        }
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

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
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
        CGSize(width: sharedTabWidth ?? titleWidths[indexPath.item], height: collectionView.bounds.height)
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
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -PageTabBar.titlePadding),

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
