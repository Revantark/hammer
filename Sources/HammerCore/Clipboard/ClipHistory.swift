import Foundation

public enum InsertOutcome: Equatable, Sendable {
    case added(evicted: [UUID])
    case movedToTop(existingID: UUID)
}

public struct DaySection: Equatable, Sendable {
    public let title: String
    public let entries: [ClipEntry]
}

/// The latest 25 clipboard entries, newest first, deduped by content.
public struct ClipHistory: Codable, Equatable, Sendable {
    public static let capacity = 25

    public private(set) var entries: [ClipEntry]

    public init(entries: [ClipEntry] = []) {
        self.entries = Array(entries.prefix(Self.capacity))
    }

    public mutating func insert(_ entry: ClipEntry) -> InsertOutcome {
        if let index = entries.firstIndex(where: { $0.contentHash == entry.contentHash }) {
            var existing = entries.remove(at: index)
            existing.copiedAt = entry.copiedAt
            entries.insert(existing, at: 0)
            return .movedToTop(existingID: existing.id)
        }
        entries.insert(entry, at: 0)
        guard entries.count > Self.capacity else { return .added(evicted: []) }
        let evicted = entries[Self.capacity...].map(\.id)
        entries.removeLast(entries.count - Self.capacity)
        return .added(evicted: evicted)
    }

    public mutating func moveToTop(id: UUID, at date: Date) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries.remove(at: index)
        entry.copiedAt = date
        entries.insert(entry, at: 0)
    }

    public mutating func removeAll() -> [UUID] {
        defer { entries.removeAll() }
        return entries.map(\.id)
    }

    public func search(_ query: String) -> [ClipEntry] {
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return entries }
        return entries.filter { entry in
            if let s = entry.snippet, fold(s).contains(q) { return true }
            if let app = entry.sourceApp, fold(app).contains(q) { return true }
            return entry.kind == .image && "image".contains(q)
        }
    }

    public static func sections(_ entries: [ClipEntry], now: Date, calendar: Calendar, locale: Locale) -> [DaySection] {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        var sections: [DaySection] = []
        var currentDay: Date?
        var bucket: [ClipEntry] = []
        func flush() {
            guard let day = currentDay, !bucket.isEmpty else { return }
            let title = calendar.isDate(day, inSameDayAs: now) ? "Today"
                : calendar.isDate(day, inSameDayAs: yesterday) ? "Yesterday"
                : formatter.string(from: day)
            sections.append(DaySection(title: title, entries: bucket))
        }
        for entry in entries {
            let day = calendar.startOfDay(for: entry.copiedAt)
            if day != currentDay {
                flush()
                currentDay = day
                bucket = []
            }
            bucket.append(entry)
        }
        flush()
        return sections
    }

    private func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
