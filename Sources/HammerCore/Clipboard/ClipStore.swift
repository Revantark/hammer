import Foundation
import os

/// Persists clipboard history: `<dir>/clipboard/index.json` + one binary plist per entry in `blobs/`.
public final class ClipStore: @unchecked Sendable {
    private static let log = Logger(subsystem: "dev.hammer", category: "clipstore")

    private let root: URL
    private let blobs: URL
    private var indexURL: URL { root.appendingPathComponent("index.json") }
    private let fm = FileManager.default

    public init(directory: URL) {
        root = directory.appendingPathComponent("clipboard", isDirectory: true)
        blobs = root.appendingPathComponent("blobs", isDirectory: true)
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
        for id in ids { try? fm.removeItem(at: blobURL(id)) }
    }

    /// Deletes blobs not referenced by history (recovers from crashes between blob and index writes).
    public func pruneOrphans(keeping ids: Set<UUID>) {
        let keep = Set(ids.map { "\($0.uuidString).plist" })
        guard let files = try? fm.contentsOfDirectory(atPath: blobs.path) else { return }
        for file in files where !keep.contains(file) {
            try? fm.removeItem(at: blobs.appendingPathComponent(file))
        }
    }

    private func blobURL(_ id: UUID) -> URL { blobs.appendingPathComponent("\(id.uuidString).plist") }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}
