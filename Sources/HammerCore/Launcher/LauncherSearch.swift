import Foundation

/// Merges results from all sources and ranks them.
/// - Typing: one list ranked by match tier ↓, usage (frecency) ↓, match score ↓, title ↑; at most `limit`.
/// - Empty query: a "Recent" section (last opened first, at most `recentLimit`), then every other result A–Z.
@MainActor public final class LauncherSearch {
    public static let recentSection = "Recent"
    public static let recentLimit = 5

    private let sources: [ResultSource]

    public init(sources: [ResultSource]) {
        self.sources = sources
    }

    public func search(_ query: String, frecency: Frecency, now: Date, limit: Int = 50) -> [LauncherResult] {
        let all = sources.flatMap { $0.results(for: query) }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return browse(all, frecency: frecency) }
        let ranked = all
            .map { (result: $0, usage: frecency.score(id: $0.id, now: now)) }
            .sorted { a, b in
                if a.result.match.tier != b.result.match.tier { return a.result.match.tier > b.result.match.tier }
                if a.usage != b.usage { return a.usage > b.usage }
                if a.result.match.score != b.result.match.score { return a.result.match.score > b.result.match.score }
                return Self.titleOrder(a.result, b.result)
            }
        return ranked.prefix(limit).map(\.result)
    }

    private func browse(_ all: [LauncherResult], frecency: Frecency) -> [LauncherResult] {
        let recent = all
            .compactMap { r in frecency.records[r.id].map { (result: r, lastUsed: $0.lastUsed) } }
            .sorted { a, b in a.lastUsed != b.lastUsed ? a.lastUsed > b.lastUsed : Self.titleOrder(a.result, b.result) }
            .prefix(Self.recentLimit)
            .map(\.result)
        let recentIDs = Set(recent.map(\.id))
        let rest = all.filter { !recentIDs.contains($0.id) }.sorted(by: Self.titleOrder)
        return recent.map { $0.inSection(Self.recentSection) } + rest
    }

    private static func titleOrder(_ a: LauncherResult, _ b: LauncherResult) -> Bool {
        a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }
}
