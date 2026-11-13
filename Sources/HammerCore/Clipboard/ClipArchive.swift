import Foundation

/// What `ClipArchive.retain` needs from an archived entry (full entries, or line headers read without decoding).
public protocol ArchivedRecord {
    var id: UUID { get }
    var contentHash: String { get }
    var copiedAt: Date { get }
}

extension ClipEntry: ArchivedRecord {}

/// Entries that fell out of the 25-entry history stay searchable for 4 days (at most 1,000, newest first).
/// Stored on disk by `ClipStore`; decoded only while the clipboard is being searched.
public enum ClipArchive {
    public static let retention: TimeInterval = 4 * 86_400
    public static let capacity = 1_000

    /// `records` newest first. Keeps, in order, everything except: `excluding` (moved elsewhere, payload kept),
    /// older copies of the same content, entries copied more than 4 days before `now`, and all but the newest 1,000.
    /// `dropped`: IDs whose payloads should be deleted.
    public static func retain<R: ArchivedRecord>(_ records: [R], now: Date, excluding: Set<UUID> = []) -> (kept: [R], dropped: [UUID]) {
        let cutoff = now.addingTimeInterval(-retention)
        var seen = Set<String>()
        var kept: [R] = []
        var dropped: [UUID] = []
        for record in records where !excluding.contains(record.id) {
            if record.copiedAt < cutoff || kept.count == capacity || !seen.insert(record.contentHash).inserted {
                dropped.append(record.id)
            } else {
                kept.append(record)
            }
        }
        return (kept, dropped)
    }
}

/// One line of `archive.tsv`: `<copiedAt>\t<uuid>\t<contentHash>\t<search key>\t<entry JSON>\n`.
/// `key` and `json` are slices of the memory-mapped file, so holding lines costs no heap for their contents.
struct ClipArchiveLine: ArchivedRecord, Sendable {
    let id: UUID
    let contentHash: String
    let copiedAt: Date
    let key: Data
    let json: Data
    /// The whole line including its newline.
    let bytes: Data

    static func encode(_ entry: ClipEntry) -> ClipArchiveLine? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let json = try? encoder.encode(entry) else { return nil }   // JSON escapes tabs and newlines
        let key = Data(ClipSearchIndex.key(for: entry))
        var bytes = Data("\(entry.copiedAt.timeIntervalSince1970)\t\(entry.id.uuidString)\t\(entry.contentHash)\t".utf8)
        bytes.append(key)
        bytes.append(0x09)
        bytes.append(json)
        bytes.append(0x0A)
        return ClipArchiveLine(id: entry.id, contentHash: entry.contentHash, copiedAt: entry.copiedAt, key: key, json: json, bytes: bytes)
    }

    /// Lines that don't parse are skipped.
    static func parse(_ data: Data) -> [ClipArchiveLine] {
        var lines: [ClipArchiveLine] = []
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 0x0A).map { $0 + 1 } ?? data.endIndex
            let line = data[start..<end]
            start = end
            let fields = line.dropLast().split(separator: 0x09, maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count == 5,
                  let seconds = Double(String(decoding: fields[0], as: UTF8.self)),
                  let id = UUID(uuidString: String(decoding: fields[1], as: UTF8.self)) else { continue }
            lines.append(ClipArchiveLine(id: id, contentHash: String(decoding: fields[2], as: UTF8.self),
                                         copiedAt: Date(timeIntervalSince1970: seconds), key: fields[3], json: fields[4], bytes: line))
        }
        return lines
    }

    func decode() -> ClipEntry? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(ClipEntry.self, from: json)
    }
}

/// A read-only view of the archive for searching: scans the mapped file's search keys and decodes only the
/// entries it returns, so searching 1,000 archived entries adds almost nothing to memory.
public struct ClipArchiveReader: Sendable {
    let lines: [ClipArchiveLine]

    public var count: Int { lines.count }

    /// Newest-first matches, skipping `excludingHashes` (content already in the history), at most `limit`.
    /// Snippets are cut to `snippetLimit` characters (rows show one line; the preview reads the payload).
    public func search(_ query: String, excludingHashes: Set<String>, limit: Int, snippetLimit: Int) -> [ClipEntry] {
        let needle = ClipSearchIndex.needle(query)
        var found: [ClipEntry] = []
        for line in lines where found.count < limit && !excludingHashes.contains(line.contentHash) {
            guard needle.isEmpty || line.key.withUnsafeBytes({ ClipSearchIndex.contains($0, needle) }),
                  let entry = line.decode() else { continue }
            found.append(Self.shortened(entry, to: snippetLimit))
        }
        return found
    }

    static func shortened(_ e: ClipEntry, to limit: Int) -> ClipEntry {
        guard let snippet = e.snippet, snippet.count > limit else { return e }
        return ClipEntry(id: e.id, kind: e.kind, copiedAt: e.copiedAt, sourceApp: e.sourceApp, contentHash: e.contentHash,
                         snippet: String(snippet.prefix(limit)), charCount: e.charCount, pixelWidth: e.pixelWidth, pixelHeight: e.pixelHeight)
    }
}
