import Foundation
import Testing
@testable import HammerCore

@MainActor final class StaticSource: ResultSource {
    let items: [LauncherResult]
    init(_ items: [LauncherResult]) { self.items = items }
    func results(for query: String) -> [LauncherResult] {
        items.compactMap { item in
            FuzzyMatcher.match(query, in: item.title).map {
                LauncherResult(id: item.id, title: item.title, typeLabel: item.typeLabel, section: item.section, match: $0, action: item.action)
            }
        }
    }
}

@MainActor @Suite struct LauncherSearchTests {
    let now = ManualClock().now()

    func search(_ apps: [AppEntry]) -> LauncherSearch {
        LauncherSearch(sources: [AppsSource(catalog: AppCatalog(scanner: FakeScanner(apps)))])
    }

    func used(_ uses: [String: Int]) -> Frecency {
        var f = Frecency()
        for (name, count) in uses { for _ in 0..<count { f.recordUse(id: "/Applications/\(name).app", at: now) } }
        return f
    }

    @Test func matchQualityBeatsUsage() {
        let r = search([app("Safari"), app("Assafe")]).search("saf", frecency: used(["Assafe": 50]), now: now)
        #expect(r.map(\.title) == ["Safari", "Assafe"])
    }

    @Test func usageBreaksTierTies() {
        let r = search([app("Safari"), app("Slack")]).search("s", frecency: used(["Slack": 5]), now: now)
        #expect(r.map(\.title) == ["Slack", "Safari"])
    }

    @Test func emptyQueryShowsMostUsedThenAlphabetical() {
        let r = search([app("Zed"), app("Notes"), app("Spotify"), app("Mail")])
            .search("", frecency: used(["Spotify": 3, "Notes": 1]), now: now)
        #expect(r.map(\.title) == ["Spotify", "Notes", "Mail", "Zed"])
    }

    @Test func limitIsRespected() {
        let apps = (0..<80).map { app("App\($0)") }
        #expect(search(apps).search("", frecency: Frecency(), now: now, limit: 50).count == 50)
    }

    @Test func mergesMultipleSources() {
        let a = StaticSource([LauncherResult(id: "a", title: "Alpha", typeLabel: "T", section: "S", match: FuzzyMatch(tier: .subsequence, score: 0), action: .openApp(path: "/a"))])
        let b = StaticSource([LauncherResult(id: "b", title: "Alps", typeLabel: "T", section: "S", match: FuzzyMatch(tier: .subsequence, score: 0), action: .openApp(path: "/b"))])
        let r = LauncherSearch(sources: [a, b]).search("alp", frecency: Frecency(), now: now)
        #expect(r.map(\.title) == ["Alps", "Alpha"])  // both prefix; shorter scores higher
    }
}
