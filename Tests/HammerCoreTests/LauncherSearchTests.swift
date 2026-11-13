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

    func usedAt(_ minutesAgo: [String: Int], count: Int = 1) -> Frecency {
        var f = Frecency()
        for (name, minutes) in minutesAgo {
            for _ in 0..<count { f.recordUse(id: "/Applications/\(name).app", at: now.addingTimeInterval(Double(-minutes * 60))) }
        }
        return f
    }

    @Test func emptyQueryShowsRecentFirstThenAlphabetical() {
        var f = usedAt(["Spotify": 120])
        for _ in 0..<5 { f.recordUse(id: "/Applications/Spotify.app", at: now.addingTimeInterval(-7_200)) }
        f.recordUse(id: "/Applications/Notes.app", at: now.addingTimeInterval(-60))  // fewer uses, but more recent
        let r = search([app("Zed"), app("Notes"), app("Spotify"), app("Mail")]).search("", frecency: f, now: now)
        #expect(r.map(\.title) == ["Notes", "Spotify", "Mail", "Zed"])
        #expect(r.map(\.section) == ["Recent", "Recent", "Applications", "Applications"])
    }

    @Test func recentSectionHoldsAtMostFive() {
        let names = ["A1", "A2", "A3", "A4", "A5", "A6", "A7"]
        let f = usedAt(Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0 + 1) }))  // A1 newest
        let r = search(names.reversed().map { app($0) }).search("", frecency: f, now: now)
        #expect(r.filter { $0.section == "Recent" }.map(\.title) == ["A1", "A2", "A3", "A4", "A5"])
        #expect(r.filter { $0.section == "Applications" }.map(\.title) == ["A6", "A7"])
    }

    @Test func noUsageMeansNoRecentSection() {
        let r = search([app("Zed"), app("Mail")]).search("", frecency: Frecency(), now: now)
        #expect(r.map(\.title) == ["Mail", "Zed"])
        #expect(Set(r.map(\.section)) == ["Applications"])
    }

    @Test func recentAppNotRepeatedInApplications() {
        let r = search([app("Mail"), app("Notes")]).search("", frecency: usedAt(["Notes": 5]), now: now)
        #expect(r.map(\.title) == ["Notes", "Mail"])
    }

    @Test func whitespaceQueryCountsAsEmpty() {
        let r = search([app("Mail"), app("Notes")]).search("  ", frecency: usedAt(["Notes": 5]), now: now)
        #expect(r.first?.section == "Recent")
    }

    @Test func typingHasNoRecentSection() {
        let r = search([app("Safari"), app("Slack")]).search("s", frecency: usedAt(["Slack": 1]), now: now)
        #expect(r.map(\.title) == ["Slack", "Safari"])
        #expect(Set(r.map(\.section)) == ["Applications"])
    }

    @Test func emptyQueryListsEveryApp() {
        let apps = (0..<80).map { app("App\($0)") }
        #expect(search(apps).search("", frecency: Frecency(), now: now, limit: 50).count == 80)
    }

    @Test func limitIsRespectedWhileTyping() {
        let apps = (0..<80).map { app("App\($0)") }
        #expect(search(apps).search("app", frecency: Frecency(), now: now, limit: 50).count == 50)
    }

    @Test func mergesMultipleSources() {
        let a = StaticSource([LauncherResult(id: "a", title: "Alpha", typeLabel: "T", section: "S", match: FuzzyMatch(tier: .subsequence, score: 0), action: .openApp(path: "/a"))])
        let b = StaticSource([LauncherResult(id: "b", title: "Alps", typeLabel: "T", section: "S", match: FuzzyMatch(tier: .subsequence, score: 0), action: .openApp(path: "/b"))])
        let r = LauncherSearch(sources: [a, b]).search("alp", frecency: Frecency(), now: now)
        #expect(r.map(\.title) == ["Alps", "Alpha"])  // both prefix; shorter scores higher
    }
}
