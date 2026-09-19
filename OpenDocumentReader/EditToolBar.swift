import UIKit

/// The row of editing tools under the bar, shown while a document is edited.
final class EditToolBar: UIView {

    /// One button of the row.
    enum Tool: CaseIterable {
        case bold, italic, underline, strikethrough
        case textColor, highlight, fontSize
        case markHighlight, markUnderline, markStrikeOut, markSquiggly, markDraw
        case undo, redo

        var symbol: String {
            switch self {
            case .bold: return "bold"
            case .italic: return "italic"
            case .underline: return "underline"
            case .strikethrough: return "strikethrough"
            case .textColor: return "character"
            case .highlight, .markHighlight: return "highlighter"
            case .fontSize: return "textformat.size"
            case .markUnderline: return "underline"
            case .markStrikeOut: return "strikethrough"
            case .markSquiggly: return "scribble.variable"
            case .markDraw: return "pencil.tip"
            case .undo: return "arrow.uturn.backward"
            case .redo: return "arrow.uturn.forward"
            }
        }

        var label: String {
            switch self {
            case .bold: return NSLocalizedString("edit_bold", comment: "")
            case .italic: return NSLocalizedString("edit_italic", comment: "")
            case .underline: return NSLocalizedString("edit_underline", comment: "")
            case .strikethrough: return NSLocalizedString("edit_strikethrough", comment: "")
            case .textColor: return NSLocalizedString("edit_text_color", comment: "")
            case .highlight: return NSLocalizedString("edit_highlight", comment: "")
            case .fontSize: return NSLocalizedString("edit_font_size", comment: "")
            case .markHighlight: return NSLocalizedString("mark_highlight", comment: "")
            case .markUnderline: return NSLocalizedString("mark_underline", comment: "")
            case .markStrikeOut: return NSLocalizedString("mark_strike_out", comment: "")
            case .markSquiggly: return NSLocalizedString("mark_squiggly", comment: "")
            case .markDraw: return NSLocalizedString("mark_draw", comment: "")
            case .undo: return NSLocalizedString("edit_undo", comment: "")
            case .redo: return NSLocalizedString("edit_redo", comment: "")
            }
        }

        /// The tool's own name in the page: what `odr.editing.toggle` and
        /// `odr.annotation.setTool` take.
        var pageName: String? {
            switch self {
            case .bold: return "bold"
            case .italic: return "italic"
            case .underline: return "underline"
            case .strikethrough: return "strikethrough"
            case .markHighlight: return "highlight"
            case .markUnderline: return "underline"
            case .markStrikeOut: return "strikeOut"
            case .markSquiggly: return "squiggly"
            case .markDraw: return "ink"
            default: return nil
            }
        }

        /// The tools that go past typing inside a paragraph - see
        /// ``Features/advancedEditing``.
        var isAdvanced: Bool {
            switch self {
            case .undo, .redo: return false
            default: return true
            }
        }

        /// Whether the button opens a menu rather than acting at once.
        var opensMenu: Bool {
            switch self {
            case .textColor, .fontSize: return true
            default: return false
            }
        }

        /// Whether a bar under the icon shows the colour the tool applies.
        var showsColor: Bool {
            switch self {
            case .textColor, .highlight, .markHighlight, .markUnderline, .markStrikeOut, .markSquiggly,
                .markDraw:
                return true
            default: return false
            }
        }

        /// A split button: the tool acts, and the chevron beside it picks the
        /// colour it acts with.
        var hasColorChevron: Bool {
            showsColor && self != .textColor
        }

        /// The colours the tool's menu offers.
        var swatches: [Swatch] {
            switch self {
            case .textColor: return EditToolBar.textColors
            case .highlight: return EditToolBar.highlightColors
            default: return EditToolBar.markColors
            }
        }

        /// The colour the tool starts with.
        var defaultColor: String? {
            switch self {
            case .textColor: return EditToolBar.textColors[0].hex
            case .highlight: return EditToolBar.highlightColors[0].hex
            case .markHighlight: return "#ffe633"
            case .markUnderline, .markStrikeOut, .markSquiggly: return "#e53935"
            case .markDraw: return "#1e88e5"
            default: return nil
            }
        }
    }

    /// What the row holds, by what the page is.
    enum Layout {
        /// a text document or a presentation
        case text
        /// a spreadsheet or a plain text file: nothing to format
        case plain
        /// a pdf, which takes marks
        case pdf

        var tools: [Tool] {
            switch self {
            case .text:
                return [
                    .bold, .italic, .underline, .strikethrough, .textColor, .highlight, .fontSize,
                    .undo, .redo,
                ]
            case .plain:
                return [.undo, .redo]
            case .pdf:
                return [.markHighlight, .markUnderline, .markStrikeOut, .markSquiggly, .markDraw, .undo]
            }
        }
    }

    /// A pick from one of the menus.
    enum Choice {
        /// `#rrggbb`, or nil for no highlight
        case color(String?)
        /// the system picker, for a colour the menu does not list
        case customColor
        /// in points
        case size(Int)
    }

    /// A colour the menus offer.
    struct Swatch {
        let name: String
        let hex: String
    }

    // the same colours as the website and OpenDocument.droid
    static let textColors = [
        Swatch(name: "color_black", hex: "#191c1e"),
        Swatch(name: "color_red", hex: "#e53935"),
        Swatch(name: "color_blue", hex: "#1e88e5"),
        Swatch(name: "color_green", hex: "#43a047"),
    ]

    static let highlightColors = [
        Swatch(name: "color_yellow", hex: "#fff59d"),
        Swatch(name: "color_green", hex: "#c5e1a5"),
        Swatch(name: "color_pink", hex: "#f8bbd0"),
        Swatch(name: "color_blue", hex: "#b3e5fc"),
    ]

    static let markColors = [
        Swatch(name: "color_yellow", hex: "#ffe633"),
        Swatch(name: "color_red", hex: "#e53935"),
        Swatch(name: "color_blue", hex: "#1e88e5"),
        Swatch(name: "color_green", hex: "#43a047"),
    ]

    static let fontSizes = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48]

    static let height: CGFloat = 44

    /// The tools shown; nil shows none and hides the row.
    var layout: Layout? {
        didSet {
            rebuild()
        }
    }

    /// Whether the advanced tools act. Without it they are shown behind a
    /// "Pro" badge, and a tap goes to `onTap`, which says what Pro is.
    var advancedEditing = true {
        didSet {
            rebuild()
        }
    }

    var onTap: ((Tool) -> Void)?
    var onChoice: ((Tool, Choice) -> Void)?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var buttons: [Tool: UIButton] = [:]
    private var bars: [Tool: UIView] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)

        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configure()
    }

    private func configure() {
        backgroundColor = .secondarySystemBackground

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: Self.height),

            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    private func rebuild() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        buttons = [:]
        bars = [:]

        guard let layout else {
            isHidden = true

            return
        }

        isHidden = false

        if !advancedEditing, layout.tools.contains(where: \.isAdvanced) {
            stack.addArrangedSubview(makeBadge())
        }

        for tool in layout.tools {
            let button = makeButton(for: tool)
            buttons[tool] = button

            guard tool.hasColorChevron else {
                stack.addArrangedSubview(button)

                continue
            }

            let pair = UIStackView(arrangedSubviews: [button, makeChevron(for: tool)])
            pair.axis = .horizontal
            pair.spacing = 0
            pair.alignment = .center
            stack.addArrangedSubview(pair)
        }
    }

    /// Says the tools behind it are Pro's.
    private func makeBadge() -> UIView {
        let label = UILabel()
        label.text = NSLocalizedString("tool_pro_badge", comment: "")
        label.font = UIFont.preferredFont(forTextStyle: .caption1).withWeight(.semibold)
        label.textColor = .white
        label.backgroundColor = tintColor
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.accessibilityIdentifier = "edit-tool-pro"

        NSLayoutConstraint.activate([
            label.heightAnchor.constraint(equalToConstant: 20),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
        ])

        return label
    }

    private func makeButton(for tool: Tool) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: tool.symbol)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)

        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = tool.label
        button.accessibilityIdentifier = "edit-tool-\(tool.symbol)"
        // filled while pressed
        button.configurationUpdateHandler = { button in
            var configuration = button.configuration
            if button.isSelected {
                configuration?.background.backgroundColor = button.tintColor
                configuration?.baseForegroundColor = .white
            } else {
                configuration?.background.backgroundColor = .clear
                configuration?.baseForegroundColor = button.tintColor
            }
            button.configuration = configuration
        }

        if tool.showsColor {
            addBar(to: button, for: tool)
        }

        if tool.opensMenu, advancedEditing || !tool.isAdvanced {
            button.menu = makeMenu(for: tool)
            button.showsMenuAsPrimaryAction = true
        } else {
            button.addAction(
                UIAction { [weak self] _ in
                    self?.onTap?(tool)
                }, for: .touchUpInside)
        }

        return button
    }

    /// The half of a split button that picks the tool's colour.
    private func makeChevron(for tool: Tool) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(scale: .small))
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 6)

        let chevron = UIButton(configuration: configuration)
        chevron.accessibilityLabel = String(
            format: NSLocalizedString("edit_color_of", comment: ""), tool.label)
        chevron.accessibilityIdentifier = "edit-tool-\(tool.symbol)-color"

        if advancedEditing || !tool.isAdvanced {
            chevron.menu = colorMenu(for: tool, swatches: tool.swatches, offersNone: tool == .highlight)
            chevron.showsMenuAsPrimaryAction = true
        } else {
            chevron.addAction(
                UIAction { [weak self] _ in
                    self?.onTap?(tool)
                }, for: .touchUpInside)
        }

        return chevron
    }

    /// A bar under the icon in the colour the tool applies.
    private func addBar(to button: UIButton, for tool: Tool) {
        let bar = UIView()
        bar.isUserInteractionEnabled = false
        bar.layer.cornerRadius = 1
        bar.layer.borderWidth = 0.5
        bar.layer.borderColor = UIColor.separator.cgColor
        bar.backgroundColor = UIColor(hex: tool.defaultColor ?? "#000000")
        bar.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(bar)

        NSLayoutConstraint.activate([
            bar.widthAnchor.constraint(equalToConstant: 16),
            bar.heightAnchor.constraint(equalToConstant: 3),
            bar.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            bar.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -3),
        ])

        bars[tool] = bar
    }

    private func makeMenu(for tool: Tool) -> UIMenu {
        switch tool {
        case .fontSize:
            return UIMenu(
                title: tool.label,
                children: Self.fontSizes.map { size in
                    UIAction(title: "\(size)") { [weak self] _ in
                        self?.onChoice?(tool, .size(size))
                    }
                })

        case .textColor:
            return colorMenu(for: tool, swatches: Self.textColors, offersNone: false)

        default:
            return UIMenu()
        }
    }

    private func colorMenu(for tool: Tool, swatches: [Swatch], offersNone: Bool) -> UIMenu {
        var children: [UIMenuElement] = swatches.map { swatch in
            UIAction(
                title: NSLocalizedString(swatch.name, comment: ""),
                image: Self.swatchImage(UIColor(hex: swatch.hex))
            ) { [weak self] _ in
                self?.onChoice?(tool, .color(swatch.hex))
            }
        }

        if offersNone {
            children.append(
                UIAction(
                    title: NSLocalizedString("color_none", comment: ""), image: UIImage(systemName: "circle.slash")
                ) { [weak self] _ in
                    self?.onChoice?(tool, .color(nil))
                })
        }

        children.append(
            UIAction(title: NSLocalizedString("color_custom", comment: ""), image: UIImage(systemName: "paintpalette"))
            { [weak self] _ in
                self?.onChoice?(tool, .customColor)
            })

        return UIMenu(title: tool.label, children: children)
    }

    /// A filled circle, so the menu shows the colour it names.
    private static func swatchImage(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 20, height: 20)

        return UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }.withRenderingMode(.alwaysOriginal)
    }

    /// Whether `tool` is drawn as the mode: a style the selection shows, or
    /// the armed marker on a pdf.
    func setPressed(_ tool: Tool, _ pressed: Bool) {
        buttons[tool]?.isSelected = pressed
    }

    func setEnabled(_ tool: Tool, _ enabled: Bool) {
        buttons[tool]?.isEnabled = enabled
    }

    /// Paints the bar under `tool` in the colour it now applies.
    func setColor(_ tool: Tool, _ color: UIColor) {
        bars[tool]?.backgroundColor = color
    }

    /// Shows the selection's size as "12 pt", or the symbol if it has none.
    func setFontSize(_ points: String?) {
        guard let button = buttons[.fontSize] else { return }

        var configuration = button.configuration
        if let points {
            configuration?.image = nil
            configuration?.title = String(
                format: NSLocalizedString("edit_font_size_points", comment: ""), points)
        } else {
            configuration?.image = UIImage(systemName: Tool.fontSize.symbol)
            configuration?.title = nil
        }
        button.configuration = configuration
    }

    /// For the tests: the colour the bar under `tool` shows.
    func color(of tool: Tool) -> UIColor? {
        bars[tool]?.backgroundColor
    }

    /// For the tests: what the size tool says.
    var fontSizeTitle: String? {
        buttons[.fontSize]?.configuration?.title
    }

    /// For the tests: whether the row starts with the Pro badge.
    var showsProBadge: Bool {
        stack.arrangedSubviews.first?.accessibilityIdentifier == "edit-tool-pro"
    }

    /// For the tests: whether the row shows `tool`.
    func shows(_ tool: Tool) -> Bool {
        buttons[tool] != nil
    }

    func isPressed(_ tool: Tool) -> Bool {
        buttons[tool]?.isSelected ?? false
    }
}

extension UIColor {

    /// From `#rrggbb`.
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)

        self.init(
            red: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1)
    }

    /// As `#rrggbb`, which is what the page takes.
    var hexString: String {
        let rgb = deviceRGB.map { Int(($0 * 255).rounded()) }

        return String(format: "#%02x%02x%02x", rgb[0], rgb[1], rgb[2])
    }

    /// As the `[r, g, b]` in 0...1 that the pdf markers take. A wide-gamut
    /// colour from the picker is clamped into sRGB.
    var deviceRGB: [Double] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: nil)

        return [red, green, blue].map { Double(min(max($0, 0), 1)) }
    }
}

extension UIFont {

    fileprivate func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: pointSize, weight: weight)
    }
}
