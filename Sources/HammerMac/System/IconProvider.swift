import AppKit
import HammerCore

/// App icons, loaded and rendered to a small 2x bitmap off the main thread, then kept in a bounded cache.
/// Loading an icon the first time can take 25–130 ms (IconServices), so it must never block scrolling.
@MainActor public final class IconProvider {
    public nonisolated static let iconPointSize: CGFloat = 28
    /// Empty margin macOS 26 icons carry on each side (art is 824 of 1024 px); trimmed so the art fills the box.
    nonisolated static let marginTrim: CGFloat = 0.09
    public typealias Loader = @Sendable (String) -> NSImage

    private var cache: LRUCache<String, NSImage>
    private var inflight: [String: Task<NSImage?, Never>] = [:]
    private let load: Loader
    private nonisolated static let queue = DispatchQueue(label: "dev.hammer.icons", qos: .userInitiated, attributes: .concurrent)

    /// Default capacity fits a typical Applications folder (~9 KB per icon).
    public init(capacity: Int = 160, load: @escaping Loader = { NSWorkspace.shared.icon(forFile: $0) }) {
        cache = LRUCache(capacity: capacity)
        self.load = load
    }

    /// The icon if it is already loaded; never blocks.
    public func cachedIcon(forPath path: String) -> NSImage? { cache.value(for: path) }

    /// Loads (once, shared by concurrent callers) and caches the icon. Nil only if rendering failed.
    public func icon(forPath path: String) async -> NSImage? {
        if let cached = cache.value(for: path) { return cached }
        if let pending = inflight[path] { return await pending.value }
        let load = self.load
        let task = Task { () -> NSImage? in
            let image = await withCheckedContinuation { (done: CheckedContinuation<CGImage?, Never>) in
                Self.queue.async { done.resume(returning: Self.render(load(path), pointSize: Self.iconPointSize)) }
            }
            return image.map { NSImage(cgImage: $0, size: NSSize(width: Self.iconPointSize, height: Self.iconPointSize)) }
        }
        inflight[path] = task
        let icon = await task.value
        inflight[path] = nil
        if let icon { cache.insert(icon, for: path) }
        return icon
    }

    public func clear() { cache.removeAll() }

    /// Draws `source`, minus its built-in margin, into a `pointSize`×`pointSize` @2x bitmap.
    /// Safe on any thread (private context).
    nonisolated static func render(_ source: NSImage, pointSize: CGFloat) -> CGImage? {
        let pixels = Int(pointSize * 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: pointSize, height: pointSize)  // before the context, which reads it
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let drawn = pointSize / (1 - 2 * marginTrim)
        let offset = -drawn * marginTrim
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        source.draw(in: NSRect(x: offset, y: offset, width: drawn, height: drawn))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}
