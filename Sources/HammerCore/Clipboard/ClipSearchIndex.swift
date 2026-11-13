import Foundation

/// Case- and diacritic-insensitive substring search over clipboard entries: the text, the source app's name,
/// and the word "image" for images. Folds each entry once and matches raw UTF-8 bytes (memmem), so searching
/// 1,000 entries of 2,000 characters takes ~2 ms; `String.contains` took ~60 ms.
public struct ClipSearchIndex: Sendable {
    public let entries: [ClipEntry]
    private let keys: [[UInt8]]

    public init(_ entries: [ClipEntry]) {
        self.entries = entries
        keys = entries.map(Self.key(for:))
    }

    /// Matching entries in index order. A blank query matches everything.
    public func search(_ query: String) -> [ClipEntry] {
        let needle = Self.needle(query)
        guard !needle.isEmpty else { return entries }
        return zip(entries, keys).compactMap { entry, key in
            key.withUnsafeBytes { Self.contains($0, needle) } ? entry : nil
        }
    }

    public static func isBlank(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Folded text, NUL, folded app name, NUL, "image" for images. NUL never appears in a query, so a match can't
    /// straddle two fields. Tabs and line breaks become 0x01 so the key fits on one line of the archive file
    /// (a query can't contain them either: the search field is one line and Tab moves the selection).
    static func key(for entry: ClipEntry) -> [UInt8] {
        var key = Array(fold(entry.snippet ?? "").utf8)
        key.append(0)
        key += fold(entry.sourceApp ?? "").utf8
        key.append(0)
        if entry.kind == .image { key += "image".utf8 }
        for i in key.indices where key[i] == 0x09 || key[i] == 0x0A || key[i] == 0x0D { key[i] = 0x01 }
        return key
    }

    /// The folded query's bytes; empty when blank.
    static func needle(_ query: String) -> [UInt8] {
        Array(fold(query.trimmingCharacters(in: .whitespacesAndNewlines)).utf8)
    }

    static func contains(_ haystack: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        needle.withUnsafeBytes { memmem(haystack.baseAddress, haystack.count, $0.baseAddress, $0.count) != nil }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
