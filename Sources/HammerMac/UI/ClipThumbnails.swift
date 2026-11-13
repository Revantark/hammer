import CoreGraphics
import Foundation
import HammerCore

/// Clipboard images for the panel:
/// - list thumbnails come from the small PNG saved at capture (never the full image), cached across opens;
/// - the big preview comes from the panel-sized file saved at capture (~2–7 ms, so it is decoded in step with the
///   arrow key); entries saved before previews existed decode the full image off the main thread once and backfill it;
/// - only one big preview is kept.
@MainActor public final class ClipThumbnails: ThumbnailSource {
    private struct ImageBox: @unchecked Sendable { let image: CGImage? }

    private let clipboard: ClipboardController
    private var listCache = LRUCache<UUID, CGImage>(capacity: ClipHistory.capacity)
    private var previewSlot: (id: UUID, image: CGImage)?

    public init(clipboard: ClipboardController) {
        self.clipboard = clipboard
    }

    var cachedPreviewCount: Int { previewSlot == nil ? 0 : 1 }

    public func listThumbnail(for id: UUID) -> CGImage? {
        if let cached = listCache.value(for: id) { return cached }
        guard let data = clipboard.listThumbnailData(id: id),
              let image = ImageThumbnailer.thumbnail(data: data, maxPixelSize: ClipboardController.listThumbnailPixels) else { return nil }
        listCache.insert(image, for: id)
        return image
    }

    public func quickPreview(for id: UUID) -> CGImage? {
        if let slot = previewSlot, slot.id == id { return slot.image }
        guard let data = clipboard.previewData(id: id),
              let image = ImageThumbnailer.thumbnail(data: data, maxPixelSize: ClipboardController.previewPixels) else { return nil }
        previewSlot = (id, image)
        return image
    }

    public func preview(for id: UUID) async -> CGImage? {
        if let slot = previewSlot, slot.id == id { return slot.image }
        let store = clipboard.store
        let size = ClipboardController.previewPixels
        let box = await Task.detached(priority: .userInitiated) { () -> ImageBox in
            guard let reps = try? store.readPayload(id: id),
                  let rep = reps.first(where: { PasteboardType.imageTypes.contains($0.type) }),
                  let image = ImageThumbnailer.thumbnail(data: rep.data, maxPixelSize: size) else { return ImageBox(image: nil) }
            if let data = ImageThumbnailer.previewData(image) { try? store.writePreview(data, id: id) }
            return ImageBox(image: image)
        }.value
        guard let image = box.image else { return nil }
        previewSlot = (id, image)
        return image
    }

    /// Called when the panel hides: drop the big preview. List thumbnails (≤25 × 36 px) stay.
    public func clear() { previewSlot = nil }
}
