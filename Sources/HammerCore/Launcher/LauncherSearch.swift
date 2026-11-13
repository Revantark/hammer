import Foundation

/// Merges results from all sources and ranks them:
/// match tier ↓, usage (frecency) ↓, match score ↓, title ↑.
@MainActor public final class LauncherSearch {
    private let sources: [ResultSource]

    public init(sources: [ResultSource]) {
        self.sources = sources
    }

    public func search(_ query: String, frecency: Frecency, now: Date, limit: Int = 50) -> [LauncherResult] {
        let ranked = sources.flatMap { $0.results(for: query) }
            .map { (result: $0, usage: frecency.score(id: $0.id, now: now)) }
            .sorted { a, b in
                if a.result.match.tier != b.result.match.tier { return a.result.match.tier > b.result.match.tier }
                if a.usage != b.usage { return a.usage > b.usage }
                if a.result.match.score != b.result.match.score { return a.result.match.score > b.result.match.score }
                return a.result.title.localizedCaseInsensitiveCompare(b.result.title) == .orderedAscending
            }
        return ranked.prefix(limit).map(\.result)
    }
}
