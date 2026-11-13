import Foundation

public struct UsageRecord: Codable, Equatable, Sendable {
    public var count: Int
    public var lastUsed: Date

    public init(count: Int, lastUsed: Date) {
        self.count = count
        self.lastUsed = lastUsed
    }
}

/// Usage-based ranking signal: how often and how recently an item was used.
public struct Frecency: Codable, Equatable, Sendable {
    public static let halfLifeDays = 7.0

    public private(set) var records: [String: UsageRecord]

    public init(records: [String: UsageRecord] = [:]) {
        self.records = records
    }

    public mutating func recordUse(id: String, at date: Date) {
        var record = records[id] ?? UsageRecord(count: 0, lastUsed: date)
        record.count += 1
        record.lastUsed = date
        records[id] = record
    }

    /// `count * 0.5^(ageDays / 7)`; 0 for unknown ids.
    public func score(id: String, now: Date) -> Double {
        guard let record = records[id] else { return 0 }
        let ageDays = max(0, now.timeIntervalSince(record.lastUsed)) / 86_400
        return Double(record.count) * pow(0.5, ageDays / Self.halfLifeDays)
    }
}

public struct FrecencyStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Missing or corrupt file → empty.
    public func load() -> Frecency {
        guard let data = try? Data(contentsOf: fileURL) else { return Frecency() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Frecency.self, from: data)) ?? Frecency()
    }

    public func save(_ frecency: Frecency) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(frecency).write(to: fileURL, options: .atomic)
    }
}
