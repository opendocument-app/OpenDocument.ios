import UIKit

/// The strip of tools under the bar: what changes the text, and nothing else.
/// Undo, redo and save are the bar's, see ``DocumentViewController``.
///
/// Every tool is one square button, and a tap does the one thing the tool is
/// for. A tool that applies a colour shows it in the bar under its icon, and a
/// **long press** opens the colours - there is no second button beside it.
/// Which tool is on comes back from the page.
///
/// Without ``advancedEditing`` the strip is locked: the highlighter still
/// works, every other tool is dimmed and offers Pro, and Pro's badge stands in
/// front of the row. One free tool of each kind is what makes the mode worth
/// opening - see ``Tool/isFree``.
final class EditToolBar: UIView {

    /// One button of the strip.
    enum Tool: CaseIterable {
        case bold, italic, underline, strikethrough
        case textColor, highlight, fontSize
        case markHighlight, markUnderline, markStrikeOut, markSquiggly, markDraw

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
            // no wavy underline in the system set, so the wave is drawn - see
            // ``EditToolBar/squigglyImage``
            case .markSquiggly: return "squiggly"
            case .markDraw: return "scribble.variable"
            }
        }

        /// The glyph itself.
        var image: UIImage? {
            self == .markSquiggly ? EditToolBar.squigglyImage : UIImage(systemName: symbol)
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
            }
        }

        /// The tool's own name in the page: what `odr.editing.toggle` and
        /// `odr.annotation.press` take.
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

        /// The one tool a locked strip still does the work of: the highlighter,
        /// under both the names it has. It is the formatting style in a text
        /// document and the marking tool on a pdf, so a reader of either kind
        /// has the same free tool.
        var isFree: Bool {
            self == .highlight || self == .markHighlight
        }

        /// Whether the tool's own colours open on a tap rather than on a long
        /// press. The text colour has no state to turn off, so a tap is the
        /// colours themselves; the size has no colour and opens its sizes.
        var opensOnTap: Bool {
            self == .textColor || self == .fontSize
        }

        /// Whether a bar under the icon shows the colour the tool applies.
        /// A toggle applies no colour, so its slot stays empty.
        var showsColor: Bool {
            defaultColor != nil
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

    /// What the strip holds, by what the page is. A sheet or a plain text file
    /// takes no formatting at all, so there is no strip over it: see
    /// ``layout`` set to nil.
    enum Layout {
        /// a text document or a presentation
        case text
        /// a pdf, which takes marks
        case pdf

        var tools: [Tool] {
            switch self {
            case .text:
                return [.bold, .italic, .underline, .strikethrough, .textColor, .highlight, .fontSize]
            case .pdf:
                return [.markHighlight, .markUnderline, .markStrikeOut, .markSquiggly, .markDraw]
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

    static let height: CGFloat = 42

    /// One tool. The slot under the icon is there on every tool, holding
    /// something or not, so the icons sit on one line, and it is just deep
    /// enough for the caption - a tool carrying nothing reads as empty for
    /// every point over that.
    private static let toolWidth: CGFloat = 44
    private static let toolHeight: CGFloat = 36
    private static let iconSize: CGFloat = 22
    private static let slotHeight: CGFloat = 10

    /// What the colour bar keeps clear of the icon. Close enough that the bar
    /// belongs to the tool, and far enough that it is not read as part of the
    /// glyph - `underline` draws a line of its own along its foot.
    private static let barGap: CGFloat = 3

    /// What a tool that only offers Pro is drawn at, against the free one
    /// beside it.
    private static let proAlpha: CGFloat = 0.45

    /// The tools shown; nil shows none and hides the strip.
    var layout: Layout? {
        didSet {
            rebuild()
        }
    }

    /// Whether the tools do their work. Without it every tool but the free one
    /// is dimmed, a tap goes to `onTap`, which says what Pro is, and Pro's
    /// badge stands in front of the row.
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
    private var icons: [Tool: UIImageView] = [:]

    /// The size the selection is in, under the size tool's icon.
    private var sizeCaption: UILabel?

    /// The size the selection is in, in points, or nil where the runs
    /// disagree. The menu marks it.
    private var selectionSize: String?

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

        // the row is as wide as the screen where the tools leave room, so that
        // the spacers at its ends centre them; where they do not fit, it keeps
        // its own width and scrolls
        let fills = stack.widthAnchor.constraint(
            greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor, constant: -16)
        fills.priority = .required

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
            fills,
        ])
    }

    /// One end of the row, which takes what the tools leave and so centres
    /// them. Two of equal width, one at each end.
    private func makeEdgeSpacer() -> UIView {
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)

        return spacer
    }

    /// Whether `tool` only offers Pro in this build, rather than doing its
    /// work.
    private func isPro(_ tool: Tool) -> Bool {
        !advancedEditing && !tool.isFree
    }

    private func rebuild() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        buttons = [:]
        bars = [:]
        icons = [:]
        sizeCaption = nil
        selectionSize = nil

        guard let layout else {
            isHidden = true

            return
        }

        isHidden = false

        let leading = makeEdgeSpacer()
        stack.addArrangedSubview(leading)

        if !advancedEditing {
            stack.addArrangedSubview(makeBadge())
        }

        for tool in layout.tools {
            let button = makeButton(for: tool)
            buttons[tool] = button
            stack.addArrangedSubview(button)
        }

        let trailing = makeEdgeSpacer()
        stack.addArrangedSubview(trailing)
        trailing.widthAnchor.constraint(equalTo: leading.widthAnchor).isActive = true

        scrollView.contentOffset = .zero
    }

    /// Says the dimmed tools beside it are Pro's.
    private func makeBadge() -> UIView {
        let label = UILabel()
        label.text = NSLocalizedString("tool_pro_badge", comment: "")
        label.font = UIFont.preferredFont(forTextStyle: .caption1).withWeight(.semibold)
        label.textColor = .white
        label.backgroundColor = tintColor
        label.textAlignment = .center
        label.layer.cornerRadius = 14
        label.clipsToBounds = true
        label.accessibilityIdentifier = "edit-tool-pro"

        NSLayoutConstraint.activate([
            label.heightAnchor.constraint(equalToConstant: 28),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])

        return label
    }

    /// The icon on one line with every other tool's, and under it the slot
    /// that carries what the tool applies or what it reads on the selection.
    private func makeButton(for tool: Tool) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero

        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = tool.label
        button.accessibilityIdentifier = "edit-tool-\(tool.symbol)"

        let icon = UIImageView(image: tool.image)
        icon.contentMode = .scaleAspectFit
        icon.tintColor = button.tintColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(icon)
        icons[tool] = icon

        // the slot is there on every tool, holding something or not, so that
        // the icons sit on one line
        let slot = UILayoutGuide()
        button.addLayoutGuide(slot)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.toolWidth),
            button.heightAnchor.constraint(equalToConstant: Self.toolHeight),

            icon.widthAnchor.constraint(equalToConstant: Self.iconSize),
            icon.heightAnchor.constraint(equalToConstant: Self.iconSize),
            icon.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            icon.topAnchor.constraint(
                equalTo: button.topAnchor, constant: (Self.toolHeight - Self.iconSize - Self.slotHeight) / 2),

            slot.topAnchor.constraint(equalTo: icon.bottomAnchor),
            slot.heightAnchor.constraint(equalToConstant: Self.slotHeight),
            slot.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            slot.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        ])

        // filled while pressed, which is what says the tool is on
        button.configurationUpdateHandler = { [weak icon] button in
            var configuration = button.configuration
            configuration?.background.backgroundColor = button.isSelected ? button.tintColor : .clear
            button.configuration = configuration

            icon?.tintColor = button.isSelected ? .white : button.tintColor
        }

        if tool.showsColor {
            addBar(to: button, in: slot, for: tool)
        } else if tool == .fontSize {
            addCaption(to: button, in: slot)
        }

        // a tool that only offers Pro is dimmed, so the free one is the one
        // that stands out
        button.alpha = isPro(tool) ? Self.proAlpha : 1

        addActions(to: button, for: tool)

        return button
    }

    /// A tap does the tool's one job, and a long press opens what it applies.
    /// Where the tool has nothing to turn off, the tap opens it instead.
    private func addActions(to button: UIButton, for tool: Tool) {
        guard !isPro(tool) else {
            button.addAction(
                UIAction { [weak self] _ in
                    self?.onTap?(tool)
                }, for: .touchUpInside)

            return
        }

        button.menu = makeMenu(for: tool)
        button.showsMenuAsPrimaryAction = tool.opensOnTap

        guard !tool.opensOnTap else { return }

        button.addAction(
            UIAction { [weak self] _ in
                self?.onTap?(tool)
            }, for: .touchUpInside)

        // VoiceOver has no long press, so the colours behind it are offered as
        // the button's own actions instead, each named "Highlight yellow"
        button.accessibilityCustomActions = colorActions(for: tool)
    }

    /// What the long press opens, as one action per colour, for a reader who
    /// cannot make that press.
    private func colorActions(for tool: Tool) -> [UIAccessibilityCustomAction] {
        let of = String(format: NSLocalizedString("edit_color_of", comment: ""), tool.label)

        var actions = tool.swatches.map { swatch in
            UIAccessibilityCustomAction(name: "\(of) \(NSLocalizedString(swatch.name, comment: ""))") {
                [weak self] _ in
                self?.onChoice?(tool, .color(swatch.hex))

                return true
            }
        }

        if tool == .highlight {
            actions.append(
                UIAccessibilityCustomAction(name: NSLocalizedString("color_none", comment: "")) { [weak self] _ in
                    self?.onChoice?(tool, .color(nil))

                    return true
                })
        }

        actions.append(
            UIAccessibilityCustomAction(name: NSLocalizedString("color_custom", comment: "")) { [weak self] _ in
                self?.onChoice?(tool, .customColor)

                return true
            })

        return actions
    }

    /// A bar in the slot, in the colour the tool applies, so that the bar is
    /// what the next tap uses.
    private func addBar(to button: UIButton, in slot: UILayoutGuide, for tool: Tool) {
        let bar = UIView()
        bar.isUserInteractionEnabled = false
        bar.layer.cornerRadius = 1
        bar.layer.borderWidth = 0.5
        bar.layer.borderColor = UIColor.separator.cgColor
        bar.backgroundColor = UIColor(hex: tool.defaultColor ?? "#000000")
        bar.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(bar)

        NSLayoutConstraint.activate([
            bar.widthAnchor.constraint(equalToConstant: 20),
            bar.heightAnchor.constraint(equalToConstant: 4),
            bar.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            bar.topAnchor.constraint(equalTo: slot.topAnchor, constant: Self.barGap),
        ])

        bars[tool] = bar
    }

    /// What the tool reads on the selection, in the slot: the size the text is
    /// in. The icon stays, so the tool is still the one it was.
    private func addCaption(to button: UIButton, in slot: UILayoutGuide) {
        let caption = UILabel()
        caption.isUserInteractionEnabled = false
        caption.font = .systemFont(ofSize: 10)
        caption.textColor = .secondaryLabel
        caption.textAlignment = .center
        caption.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(caption)

        NSLayoutConstraint.activate([
            caption.leadingAnchor.constraint(equalTo: slot.leadingAnchor),
            caption.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
            caption.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
        ])

        sizeCaption = caption
    }

    private func makeMenu(for tool: Tool) -> UIMenu {
        guard tool != .fontSize else {
            return sizeMenu()
        }

        return colorMenu(for: tool, swatches: tool.swatches, offersNone: tool == .highlight)
    }

    /// The fourteen sizes, with the one the text is in marked.
    private func sizeMenu() -> UIMenu {
        UIMenu(
            title: Tool.fontSize.label,
            children: Self.fontSizes.map { size in
                let action = UIAction(title: "\(size)") { [weak self] _ in
                    self?.onChoice?(.fontSize, .size(size))
                }
                action.state = "\(size)" == selectionSize ? .on : .off

                return action
            })
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

    /// A wave standing for an underline, at the weight of the system glyphs
    /// beside it. The system set has no wavy underline, and `scribble` is the
    /// Draw tool's.
    private static let squigglyImage: UIImage = {
        let size = CGSize(width: iconSize, height: iconSize)
        let humps = 4
        let width: CGFloat = 16
        let step = width / CGFloat(humps)
        let baseline: CGFloat = 14
        // a quadratic curve reaches half of what its control point offers
        let reach: CGFloat = 5

        let wave = UIBezierPath()
        wave.move(to: CGPoint(x: 3, y: baseline))
        for hump in 0..<humps {
            let start = 3 + step * CGFloat(hump)
            wave.addQuadCurve(
                to: CGPoint(x: start + step, y: baseline),
                controlPoint: CGPoint(x: start + step / 2, y: baseline + (hump.isMultiple(of: 2) ? -reach : reach)))
        }
        wave.lineWidth = 1.7
        wave.lineCapStyle = .round

        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.black.setStroke()
            wave.stroke()
        }.withRenderingMode(.alwaysTemplate)
    }()

    /// A filled circle, so the menu shows the colour it names.
    private static func swatchImage(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 20, height: 20)

        return UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }.withRenderingMode(.alwaysOriginal)
    }

    /// Whether `tool` is drawn as the mode: a style the selection shows, or
    /// the armed marker on a pdf. A locked strip shows none of it, since
    /// nothing it dims is on.
    func setPressed(_ tool: Tool, _ pressed: Bool) {
        buttons[tool]?.isSelected = pressed && !isPro(tool)
    }

    /// Paints the bar under `tool` in the colour it now applies.
    func setColor(_ tool: Tool, _ color: UIColor) {
        bars[tool]?.backgroundColor = color
    }

    /// Captions the size tool with "12 pt", or with nothing where the runs
    /// disagree.
    func setFontSize(_ points: String?) {
        selectionSize = points

        sizeCaption?.text = points.map {
            String(format: NSLocalizedString("edit_font_size_points", comment: ""), $0)
        }

        // the mark moves with the selection, and a menu is built once
        if let button = buttons[.fontSize], !isPro(.fontSize) {
            button.menu = sizeMenu()
        }
    }

    /// For the tests: the colour the bar under `tool` shows.
    func color(of tool: Tool) -> UIColor? {
        bars[tool]?.backgroundColor
    }

    /// For the tests: what the size tool says.
    var fontSizeTitle: String? {
        sizeCaption?.text
    }

    /// For the tests: whether the row carries the Pro badge, in front of the
    /// tools.
    var showsProBadge: Bool {
        stack.arrangedSubviews.contains { $0.accessibilityIdentifier == "edit-tool-pro" }
    }

    /// For the tests: whether the row shows `tool`.
    func shows(_ tool: Tool) -> Bool {
        buttons[tool] != nil
    }

    /// For the tests: whether `tool` is dimmed, which is how a locked strip
    /// says the tool is Pro's.
    func isDimmed(_ tool: Tool) -> Bool {
        (buttons[tool]?.alpha ?? 1) < 1
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
