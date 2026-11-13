import CoreGraphics
import Foundation
import HammerCore

/// Downscaled clipboard images, decoded on demand from stored payloads and kept in a small LRU.
@MainActor public final class ClipThumbnails: ThumbnailSource {
    private struct Key: Hashable { let id: UUID; let size: Int }

    private let clipboard: ClipboardController
    private var cache = LRUCache<Key, CGImage>(capacity: ClipHistory.capacity + 1)

    public init(clipboard: ClipboardController) {
        self.clipboard = clipboard
    }

    public func thumbnail(for id: UUID, maxPixelSize: Int) -> CGImage? {
        let key = Key(id: id, size: maxPixelSize)
        if let cached = cache.value(for: key) { return cached }
        guard let image = clipboard.payload(id: id)?.first(where: { PasteboardType.imageTypes.contains($0.type) }),
              let thumb = ImageThumbnailer.thumbnail(data: image.data, maxPixelSize: maxPixelSize) else { return nil }
        cache.insert(thumb, for: key)
        return thumb
    }

    public func clear() { cache.removeAll() }
}
