import Foundation
import Testing
@testable import HammerCore

@MainActor @Suite struct AppCatalogTests {
    @Test func catalogSortsByName() {
        let catalog = AppCatalog(scanner: FakeScanner([app("Slack"), app("Safari")]))
        #expect(catalog.apps.map(\.name) == ["Safari", "Slack"])
    }

    @Test func dedupesByBundleIDPreferringApplications() {
        let catalog = AppCatalog(scanner: FakeScanner([
            app("Foo", "/Users/x/Applications/Foo.app", bundleID: "com.foo"),
            app("Foo", "/Applications/Foo.app", bundleID: "com.foo"),
        ]))
        #expect(catalog.apps == [app("Foo", "/Applications/Foo.app", bundleID: "com.foo")])
    }

    @Test func differentBundleIDsSameNameBothKept() {
        let catalog = AppCatalog(scanner: FakeScanner([
            app("Foo", "/Applications/Foo.app", bundleID: "com.foo"),
            app("Foo", "/Users/x/Applications/Foo.app", bundleID: "com.other"),
        ]))
        #expect(catalog.apps.count == 2)
    }

    @Test func appsWithoutBundleIDAreKept() {
        let catalog = AppCatalog(scanner: FakeScanner([
            AppEntry(name: "A", path: "/Applications/A.app", bundleID: nil),
            AppEntry(name: "B", path: "/Applications/B.app", bundleID: nil),
        ]))
        #expect(catalog.apps.count == 2)
    }

    @Test func watcherChangeReloads() {
        let scanner = FakeScanner([app("Safari")])
        let catalog = AppCatalog(scanner: scanner)
        let watcher = FakeWatcher()
        var changes = 0
        catalog.onChange = { changes += 1 }
        catalog.startWatching(watcher)
        #expect(watcher.startedPaths == scanner.roots)
        scanner.apps.append(app("Notes"))
        watcher.fire()
        #expect(catalog.apps.map(\.name) == ["Notes", "Safari"])
        #expect(changes == 1)
    }

    @Test func appsSourceReturnsMatches() {
        let source = AppsSource(catalog: AppCatalog(scanner: FakeScanner([app("Safari"), app("Notes")])))
        let results = source.results(for: "saf")
        #expect(results.count == 1)
        #expect(results.first?.action == .openApp(path: "/Applications/Safari.app"))
        #expect(results.first?.typeLabel == "Application")
        #expect(results.first?.section == "Applications")
        #expect(results.first?.id == "/Applications/Safari.app")
    }
}
