import AppKit

/// "Frost" look: frosted dark glass, values from the approved mockup.
public enum Theme {
    public static let cornerRadius: CGFloat = 14
    public static let launcherWidth: CGFloat = 620
    public static let clipboardWidth: CGFloat = 760
    public static let rowHeight: CGFloat = 40
    public static let clipRowHeight: CGFloat = 32
    public static let headerHeight: CGFloat = 26
    public static let searchHeight: CGFloat = 54
    public static let footerHeight: CGFloat = 34
    public static let clipboardBodyHeight: CGFloat = 330
    public static let maxVisibleRows = 8
    public static let searchFontSize: CGFloat = 19
    public static let iconSize: CGFloat = 28
    public static let listInset: CGFloat = 8

    public static let primaryText = NSColor(white: 1, alpha: 0.92)
    public static let secondaryText = NSColor(white: 1, alpha: 0.45)
    public static let selectionFill = NSColor(white: 1, alpha: 0.10)
    public static let border = NSColor(white: 1, alpha: 0.12)
    public static let divider = NSColor(white: 1, alpha: 0.08)
    public static let footerFill = NSColor(white: 0, alpha: 0.15)
    public static let keyCapFill = NSColor(white: 1, alpha: 0.10)
    public static let keyCapText = NSColor(white: 1, alpha: 0.75)

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }
}
