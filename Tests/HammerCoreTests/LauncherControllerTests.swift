import Foundation
import Testing
@testable import HammerCore

@MainActor @Suite struct LauncherControllerTests {
    func make(_ apps: [AppEntry], storeURL: URL, launcher: FakeAppLauncher = FakeAppLauncher()) -> LauncherController {
        let search = LauncherSearch(sources: [AppsSource(catalog: AppCatalog(scanner: FakeScanner(apps)))])
        return LauncherController(search: search, store: FrecencyStore(fileURL: storeURL), launcher: launcher, clock: ManualClock())
    }

    @Test func performOpensApp() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let launcher = FakeAppLauncher()
        let c = make([app("Safari")], storeURL: dir.appendingPathComponent("f.json"), launcher: launcher)
        c.perform(c.results(for: "saf")[0])
        #expect(launcher.opened == ["/Applications/Safari.app"])
    }

    @Test func performRecordsUsageAndPersists() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let url = dir.appendingPathComponent("f.json")
        let c = make([app("Safari")], storeURL: url)
        c.perform(c.results(for: "saf")[0])
        #expect(FrecencyStore(fileURL: url).load().records["/Applications/Safari.app"]?.count == 1)
    }

    @Test func performedAppRanksHigherNextTime() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let c = make([app("Safari"), app("Slack")], storeURL: dir.appendingPathComponent("f.json"))
        #expect(c.results(for: "s").map(\.title) == ["Safari", "Slack"])
        c.perform(c.results(for: "s")[1])
        #expect(c.results(for: "s").map(\.title) == ["Slack", "Safari"])
    }

    @Test func usageLoadedFromStoreAtInit() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let url = dir.appendingPathComponent("f.json")
        var f = Frecency()
        f.recordUse(id: "/Applications/Slack.app", at: ManualClock().now())
        try FrecencyStore(fileURL: url).save(f)
        #expect(make([app("Safari"), app("Slack")], storeURL: url).results(for: "s").map(\.title) == ["Slack", "Safari"])
    }

    @Test func saveFailureStillLaunches() {
        let launcher = FakeAppLauncher()
        let c = make([app("Safari")], storeURL: URL(fileURLWithPath: "/nonexistent-hammer-dir/sub/f.json"), launcher: launcher)
        c.perform(c.results(for: "saf")[0])
        #expect(launcher.opened.count == 1)
    }
}
