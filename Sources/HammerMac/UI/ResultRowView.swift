import AppKit

/// Row background: soft rounded fill when selected. Never uses NSTableView's own selection.
final class SelectionRowView: NSTableRowView {
    var isItemSelected = false {
        didSet { if oldValue != isItemSelected { needsDisplay = true } }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isItemSelected else { return }
        Theme.selectionFill.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: Theme.listInset, dy: 1), xRadius: 8, yRadius: 8).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}

@MainActor
func makeLabel(_ font: NSFont, _ color: NSColor) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.font = font
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    label.cell?.truncatesLastVisibleLine = true
    return label
}

/// Small muted section label ("Applications", "Today").
final class HeaderCellView: NSView {
    let label = makeLabel(Theme.font(11, .semibold), Theme.secondaryText)

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        let h = label.intrinsicContentSize.height
        label.frame = NSRect(x: Theme.listInset + 10, y: 3, width: bounds.width - 2 * (Theme.listInset + 10), height: h)
    }
}

/// Icon + title + optional trailing label.
final class ItemCellView: NSView {
    let iconView = NSImageView()
    let title = makeLabel(Theme.font(14), Theme.primaryText)
    let trailing = makeLabel(Theme.font(12), Theme.secondaryText)
    var iconSize: CGFloat = Theme.iconSize

    override init(frame: NSRect) {
        super.init(frame: frame)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        trailing.alignment = .right
        [iconView, title, trailing].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        let x0 = Theme.listInset + 10
        iconView.frame = NSRect(x: x0, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        let trailingWidth = trailing.stringValue.isEmpty ? 0 : min(trailing.intrinsicContentSize.width, 160)
        let trailingX = bounds.width - Theme.listInset - 10 - trailingWidth
        let th = trailing.intrinsicContentSize.height
        trailing.frame = NSRect(x: trailingX, y: (bounds.height - th) / 2, width: trailingWidth, height: th)
        let titleX = iconView.frame.maxX + 10
        let h = title.intrinsicContentSize.height
        title.frame = NSRect(x: titleX, y: (bounds.height - h) / 2, width: max(0, trailingX - 8 - titleX), height: h)
    }
}

/// A rounded key cap like "↵" or "⌥X".
final class KeyCapView: NSView {
    let text: String
    private let attributes: [NSAttributedString.Key: Any] = [.font: Theme.font(11, .medium), .foregroundColor: Theme.keyCapText]

    init(_ text: String) {
        self.text = text
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize {
        let size = (text as NSString).size(withAttributes: attributes)
        return NSSize(width: ceil(size.width) + 12, height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.keyCapFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

/// Footer hints: "Open ↵   Clipboard ⌥X".
final class KeyHintsView: NSStackView {
    private(set) var hints: [(label: String, key: String)] = []

    func setHints(_ hints: [(label: String, key: String)]) {
        self.hints = hints
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        orientation = .horizontal
        spacing = 6
        for (i, hint) in hints.enumerated() {
            if i > 0 { addArrangedSubview(NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 1))) }
            addArrangedSubview(makeLabel(Theme.font(12), Theme.secondaryText).withText(hint.label))
            addArrangedSubview(KeyCapView(hint.key))
        }
    }

    var text: String { hints.map { "\($0.label) \($0.key)" }.joined(separator: "  ") }
}

/// Passes clicks through (used for the border overlay).
final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension NSTextField {
    func withText(_ s: String) -> NSTextField {
        stringValue = s
        return self
    }
}
