import AppKit
import HammerCore

/// App icons rendered once to a small 2x bitmap and kept in a bounded cache.
@MainActor public final class IconProvider {
    public static let iconPointSize: CGFloat = 24

    private var cache: LRUCache<String, NSImage>
    private let load: (String) -> NSImage

    public init(capacity: Int = 64, load: @escaping (String) -> NSImage = { NSWorkspace.shared.icon(forFile: $0) }) {
        cache = LRUCache(capacity: capacity)
        self.load = load
    }

    public func icon(forPath path: String) -> NSImage {
        if let cached = cache.value(for: path) { return cached }
        let icon = Self.render(load(path), pointSize: Self.iconPointSize)
        cache.insert(icon, for: path)
        return icon
    }

    public func clear() { cache.removeAll() }

    static func render(_ source: NSImage, pointSize: CGFloat) -> NSImage {
        let pixels = Int(pointSize * 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return source }
        rep.size = NSSize(width: pointSize, height: pointSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: NSRect(x: 0, y: 0, width: pointSize, height: pointSize))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
