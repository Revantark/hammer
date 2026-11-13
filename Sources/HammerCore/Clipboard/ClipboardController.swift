import Foundation
import os

@MainActor public protocol PasteboardAccess: AnyObject {
    var changeCount: Int { get }
    func snapshot() -> PasteboardSnapshot
    /// Replaces the pasteboard contents; returns the new change count.
    @discardableResult func write(_ reps: [Representation]) -> Int
}

@MainActor public protocol PasteSending: AnyObject {
    var isTrusted: Bool { get }
    func sendPaste()
    func requestTrust()
}

public enum PasteOutcome: Equatable, Sendable {
    case pasted
    /// No Accessibility permission: the entry is on the clipboard, the user presses ⌘V.
    case copiedOnly
}

@MainActor public final class ClipboardController {
    public static let pollInterval: TimeInterval = 0.25
    /// List-row thumbnail size: 18 pt at 2x.
    public static let listThumbnailPixels = 36
    /// Saved preview size: fills the preview pane at 2x.
    public static let previewPixels = 840
    private static let log = Logger(subsystem: "dev.hammer", category: "clipboard")

    private let pasteboard: PasteboardAccess
    public nonisolated let store: ClipStore
    private let clock: HammerClock
    private let makeID: () -> UUID
    private var lastSeenChangeCount: Int

    public private(set) var history: ClipHistory
    public var onChange: (() -> Void)?

    /// Rows show ~one line of an archived entry; the preview reads the payload.
    static let archivedSnippetLimit = 300
    /// The newest archived matches shown per search; typing more narrows them.
    public static let archivedResultLimit = 200
    /// The archive (entries older than the 25), opened only while searching (see `search`, `releaseSearch`);
    /// dropped after any change and reopened on the next search.
    private var archiveReader: ClipArchiveReader?
    public var isArchiveLoaded: Bool { archiveReader != nil }

    public init(pasteboard: PasteboardAccess, store: ClipStore, clock: HammerClock, makeID: @escaping () -> UUID = UUID.init) {
        self.pasteboard = pasteboard
        self.store = store
        self.clock = clock
        self.makeID = makeID
        history = store.loadHistory()
        lastSeenChangeCount = pasteboard.changeCount
        store.pruneOrphans(keeping: Set(history.entries.map(\.id) + store.archiveIDs()))
    }

    /// No query: the 25 history entries. Otherwise matches from the history, then from the last 4 days' archive.
    public func search(_ query: String) -> [ClipEntry] {
        let recent = history.search(query)
        guard !ClipSearchIndex.isBlank(query) else { return recent }
        let reader = archiveReader ?? {
            updateArchive()   // drops what aged out since the last copy
            return store.openArchive()
        }()
        archiveReader = reader
        return recent + reader.search(query, excludingHashes: Set(history.entries.map(\.contentHash)),
                                      limit: Self.archivedResultLimit, snippetLimit: Self.archivedSnippetLimit)
    }

    /// The panel closed: drop the archive from memory.
    public func releaseSearch() {
        archiveReader = nil
    }

    /// Called on a timer. Captures a new copy if the pasteboard changed since the last poll.
    public func poll() {
        let count = pasteboard.changeCount
        guard count != lastSeenChangeCount else { return }
        lastSeenChangeCount = count
        guard let candidate = ClipClassifier.classify(pasteboard.snapshot(), id: makeID(), at: clock.now()) else { return }

        switch history.insert(candidate.entry) {
        case .added(let evicted):
            do {
                try store.writePayload(candidate.representations, id: candidate.entry.id)
                if candidate.entry.kind == .image { try writeImageThumbnails(candidate) }
            } catch {
                Self.log.error("Writing clipboard payload failed: \(error.localizedDescription, privacy: .public)")
            }
            if !evicted.isEmpty { updateArchive(adding: evicted) }
        case .movedToTop:
            break
        }
        archiveReader = nil
        save()
        onChange?()
    }

    /// Puts the entry back on the pasteboard, moves it to the top, then pastes (or asks for permission).
    /// An archived entry moves back into the history (it's the newest copy again).
    public func paste(id: UUID, sender: PasteSending, beforePaste: () -> Void) -> PasteOutcome? {
        if history.entries.contains(where: { $0.id == id }) {
            guard let reps = payload(id: id) else { return nil }
            lastSeenChangeCount = pasteboard.write(reps)
            history.moveToTop(id: id, at: clock.now())
        } else {
            guard var entry = store.archivedEntry(id: id), let reps = payload(id: id) else { return nil }
            lastSeenChangeCount = pasteboard.write(reps)
            entry.copiedAt = clock.now()
            switch history.insert(entry) {
            case .added(let evicted):
                updateArchive(adding: evicted, excluding: [id])
            case .movedToTop:   // the same content is already in the history
                updateArchive(excluding: [id])
                store.deletePayloads([id])
            }
        }
        save()
        beforePaste()
        guard sender.isTrusted else {
            sender.requestTrust()
            return .copiedOnly
        }
        sender.sendPaste()
        return .pasted
    }

    public func listThumbnailData(id: UUID) -> Data? {
        store.readThumbnail(id: id)
    }

    public func previewData(id: UUID) -> Data? {
        store.readPreview(id: id)
    }

    /// Decodes the full image once: saves the panel preview, then the list thumbnail made from that preview.
    private func writeImageThumbnails(_ candidate: ClipCandidate) throws {
        guard let image = candidate.representations.first(where: { PasteboardType.imageTypes.contains($0.type) }),
              let preview = ImageThumbnailer.thumbnail(data: image.data, maxPixelSize: Self.previewPixels),
              let previewData = ImageThumbnailer.previewData(preview) else { return }
        try store.writePreview(previewData, id: candidate.entry.id)
        guard let thumb = ImageThumbnailer.thumbnail(data: previewData, maxPixelSize: Self.listThumbnailPixels),
              let png = ImageThumbnailer.pngData(thumb) else { return }
        try store.writeThumbnail(png, id: candidate.entry.id)
    }

    public func payload(id: UUID) -> [Representation]? {
        try? store.readPayload(id: id)
    }

    public func clearAll() {
        store.deletePayloads(history.removeAll())
        store.deleteArchive()
        archiveReader = nil
        store.pruneOrphans(keeping: [])
        save()
        onChange?()
    }

    private func updateArchive(adding evicted: [ClipEntry] = [], excluding: Set<UUID> = []) {
        store.deletePayloads(store.updateArchive(adding: evicted, excluding: excluding, now: clock.now()))
        archiveReader = nil
    }

    private func save() {
        do {
            try store.saveHistory(history)
        } catch {
            Self.log.error("Saving clipboard history failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
