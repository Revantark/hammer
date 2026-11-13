import Foundation
import os

/// Persists clipboard history: `<dir>/clipboard/index.json` + one binary plist per entry in `blobs/`.
public final class ClipStore: @unchecked Sendable {
    private static let log = Logger(subsystem: "dev.hammer", category: "clipstore")

    private let root: URL
    private let blobs: URL
    private let thumbs: URL
    private let previews: URL
    private var indexURL: URL { root.appendingPathComponent("index.json") }
    private var archiveURL: URL { root.appendingPathComponent("archive.tsv") }
    private let fm = FileManager.default

    public init(directory: URL) {
        root = directory.appendingPathComponent("clipboard", isDirectory: true)
        blobs = root.appendingPathComponent("blobs", isDirectory: true)
        thumbs = root.appendingPathComponent("thumbs", isDirectory: true)
        previews = root.appendingPathComponent("previews", isDirectory: true)
    }

    /// Missing → empty. Corrupt → empty, and the bad file is renamed to `index.corrupt.json`.
    public func loadHistory() -> ClipHistory {
        guard let data = try? Data(contentsOf: indexURL) else { return ClipHistory() }
        do {
            return try decoder().decode(ClipHistory.self, from: data)
        } catch {
            Self.log.error("Corrupt clipboard index, starting empty: \(error.localizedDescription, privacy: .public)")
            let quarantine = root.appendingPathComponent("index.corrupt.json")
            try? fm.removeItem(at: quarantine)
            try? fm.moveItem(at: indexURL, to: quarantine)
            return ClipHistory()
        }
    }

    public func saveHistory(_ history: ClipHistory) throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(history).write(to: indexURL, options: .atomic)
    }

    // MARK: Archive
    // `archive.tsv`, newest first, one `ClipArchiveLine` per entry. Updates read only the line headers from the
    // memory-mapped file and search scans its pre-folded keys, so neither decodes the archive (decoding 1,000 long
    // entries left ~5 MB of heap behind).

    /// Adds `entries` (newest first) in front, removes `excluding`, applies `ClipArchive.retain`, rewrites the file.
    /// Returns the IDs whose payloads should be deleted.
    public func updateArchive(adding entries: [ClipEntry], excluding: Set<UUID> = [], now: Date) -> [UUID] {
        let added = entries.compactMap(ClipArchiveLine.encode)
        let existing = archiveLines()
        let (kept, dropped) = ClipArchive.retain(added + existing, now: now, excluding: excluding)
        guard kept.count != existing.count || !added.isEmpty || !dropped.isEmpty else { return [] }
        do {
            if kept.isEmpty {
                deleteArchive()
            } else {
                try fm.createDirectory(at: root, withIntermediateDirectories: true)
                var out = Data(capacity: kept.reduce(0) { $0 + $1.bytes.count })
                for line in kept { out.append(line.bytes) }
                try out.write(to: archiveURL, options: .atomic)
            }
        } catch {
            Self.log.error("Saving clipboard archive failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        return dropped
    }

    public func openArchive() -> ClipArchiveReader {
        ClipArchiveReader(lines: archiveLines())
    }

    /// Every archived entry, newest first. Lines that don't decode are skipped.
    public func loadArchive() -> [ClipEntry] {
        archiveLines().compactMap { $0.decode() }
    }

    public func archivedEntry(id: UUID) -> ClipEntry? {
        archiveLines().first { $0.id == id }?.decode()
    }

    public func archiveIDs() -> [UUID] {
        archiveLines().map(\.id)
    }

    public func deleteArchive() {
        try? fm.removeItem(at: archiveURL)
    }

    private func archiveLines() -> [ClipArchiveLine] {
        guard let data = try? Data(contentsOf: archiveURL, options: .alwaysMapped) else { return [] }
        return ClipArchiveLine.parse(data)
    }

    public func writePayload(_ reps: [Representation], id: UUID) throws {
        try fm.createDirectory(at: blobs, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(reps).write(to: blobURL(id), options: .atomic)
    }

    public func readPayload(id: UUID) throws -> [Representation] {
        try PropertyListDecoder().decode([Representation].self, from: Data(contentsOf: blobURL(id)))
    }

    public func deletePayloads(_ ids: [UUID]) {
        for id in ids {
            try? fm.removeItem(at: blobURL(id))
            try? fm.removeItem(at: thumbURL(id))
            try? fm.removeItem(at: previewURL(id))
        }
    }

    /// Small list thumbnail (PNG) saved at capture so opening the panel never decodes full images.
    public func writeThumbnail(_ png: Data, id: UUID) throws {
        try fm.createDirectory(at: thumbs, withIntermediateDirectories: true)
        try png.write(to: thumbURL(id), options: .atomic)
    }

    public func readThumbnail(id: UUID) -> Data? {
        try? Data(contentsOf: thumbURL(id))
    }

    /// Panel-sized preview (JPEG, or PNG when transparent) saved at capture, so arrowing onto an image
    /// decodes a small file instead of the full screenshot.
    public func writePreview(_ data: Data, id: UUID) throws {
        try fm.createDirectory(at: previews, withIntermediateDirectories: true)
        try data.write(to: previewURL(id), options: .atomic)
    }

    public func readPreview(id: UUID) -> Data? {
        try? Data(contentsOf: previewURL(id))
    }

    /// Deletes blobs not referenced by history (recovers from crashes between blob and index writes).
    public func pruneOrphans(keeping ids: Set<UUID>) {
        for (dir, ext) in [(blobs, "plist"), (thumbs, "png"), (previews, "img")] {
            let keep = Set(ids.map { "\($0.uuidString).\(ext)" })
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for file in files where !keep.contains(file) {
                try? fm.removeItem(at: dir.appendingPathComponent(file))
            }
        }
    }

    private func blobURL(_ id: UUID) -> URL { blobs.appendingPathComponent("\(id.uuidString).plist") }
    private func thumbURL(_ id: UUID) -> URL { thumbs.appendingPathComponent("\(id.uuidString).png") }
    /// ".img": the format (JPEG or PNG) is detected from the bytes.
    private func previewURL(_ id: UUID) -> URL { previews.appendingPathComponent("\(id.uuidString).img") }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}
