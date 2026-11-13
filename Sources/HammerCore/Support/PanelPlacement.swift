import CoreGraphics

public enum PanelPlacement {
    /// The panel's top edge sits this fraction of the screen height below the top.
    public static let topOffsetFraction: CGFloat = 0.22

    public static func frame(size: CGSize, in screen: CGRect) -> CGRect {
        let x = screen.minX + (screen.width - size.width) / 2
        let top = screen.maxY - topOffsetFraction * screen.height
        var y = top - size.height
        if y < screen.minY { y = screen.minY }
        if y + size.height > screen.maxY { y = screen.maxY - size.height }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
