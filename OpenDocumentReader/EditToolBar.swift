import UIKit

/// The row of editing tools under the bar, shown while a document is edited.
/// As on the website: the bar keeps the way in and out of an edit, and this
/// row grows beneath it with what the open document takes.
final class EditToolBar: UIView {

    /// One button of the row.
    enum Tool: CaseIterable {
        case bold, italic, underline, strikethrough
        case textColor, highlight, fontSize
        case markHighlight, markUnderline, markStrikeOut, markSquiggly, markDraw, markColor
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
            case .markColor: return "paintpalette"
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
            case .markColor: return NSLocalizedString("mark_color", comment: "")
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
            case .textColor, .highlight, .fontSize, .markColor: return true
            default: return false
            }
        }
    }

    /// What the row holds, by what the page is.
    enum Layout {
        /// a text document, a presentation or a plain text file
        case text
        /// a spreadsheet or a plain text file: nothing to format, so only the
        /// way back
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
                return [.markHighlight, .markUnderline, .markStrikeOut, .markSquiggly, .markDraw, .markColor, .undo]
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

    /// Whether the menus open: in a build without the advanced editing a tap
    /// goes to `onTap` instead, which says what Pro is.
    var menusEnabled = true {
        didSet {
            rebuild()
        }
    }

    var onTap: ((Tool) -> Void)?
    var onChoice: ((Tool, Choice) -> Void)?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var buttons: [Tool: UIButton] = [:]

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

        guard let layout else {
            isHidden = true

            return
        }

        isHidden = false

        for tool in layout.tools {
            let button = makeButton(for: tool)
            buttons[tool] = button
            stack.addArrangedSubview(button)
        }
    }

    private func makeButton(for tool: Tool) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: tool.symbol)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)

        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = tool.label
        button.accessibilityIdentifier = "edit-tool-\(tool.symbol)"
        // filled while it is the mode, as the pen on the website is
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

        if tool.opensMenu, menusEnabled {
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
        case .highlight:
            return colorMenu(for: tool, swatches: Self.highlightColors, offersNone: true)
        case .markColor:
            return colorMenu(for: tool, swatches: Self.markColors, offersNone: false)

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
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: nil)

        return String(format: "#%02x%02x%02x", Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    /// As the `[r, g, b]` in 0...1 that `odr.annotation.setColor` takes.
    var deviceRGB: [Double] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: nil)

        return [Double(red), Double(green), Double(blue)]
    }
}
