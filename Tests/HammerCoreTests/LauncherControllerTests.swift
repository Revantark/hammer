import Foundation
import Testing
@testable import HammerCore

@MainActor @Suite struct LauncherControllerTests {
    func make(_ apps: [AppEntry], storeURL: URL, launcher: FakeAppLauncher = FakeAppLauncher(),
              pasteboard: FakePasteboard = FakePasteboard()) -> LauncherController {
        let search = LauncherSearch(sources: [AppsSource(catalog: AppCatalog(scanner: FakeScanner(apps)))])
        return LauncherController(search: search, store: FrecencyStore(fileURL: storeURL), launcher: launcher,
                                  pasteboard: pasteboard, clock: ManualClock())
    }

    @Test func calculationComesFirstAndEnterCopiesWithoutRecordingUsage() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let url = dir.appendingPathComponent("f.json")
        let launcher = FakeAppLauncher(), pasteboard = FakePasteboard()
        let c = make([app("2048 Game")], storeURL: url, launcher: launcher, pasteboard: pasteboard)
        let results = c.results(for: "20*48")
        #expect(results.first?.title == "960")
        #expect(results.first?.section == Calculator.section)
        c.perform(results[0])
        #expect(pasteboard.written == [[rep(PasteboardType.plainText, "960")]])
        #expect(launcher.opened.isEmpty)
        #expect(FrecencyStore(fileURL: url).load().records.isEmpty)
    }

    @Test func noCalculationForAppNames() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let c = make([app("1Password")], storeURL: dir.appendingPathComponent("f.json"))
        #expect(c.results(for: "1pass").map(\.title) == ["1Password"])
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
        let before = c.results(for: "s").map(\.title)
        #expect(before == ["Slack", "Safari"])  // shorter name wins with no usage
        c.perform(c.results(for: "s")[1])
        #expect(c.results(for: "s").map(\.title) == ["Safari", "Slack"])
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
