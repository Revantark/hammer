import AppKit
import Testing
import HammerCore
@testable import HammerMac

@MainActor @Suite struct AppCompositionTests {
    func make(_ dir: URL, applier: FakeHotkeyApplier = FakeHotkeyApplier(), spotlightOwns: Bool = false,
              watcher: FakeWatcher = FakeWatcher()) -> AppComposition {
        AppComposition(dataDirectory: dir, pasteboard: FakePasteboard(), scanner: FakeScanner([app("Safari")]), watcher: watcher,
                       appLauncher: FakeAppLauncher(), pasteSender: FakePasteSender(), hotkeys: applier, clock: ManualClock(),
                       runningApps: running, trash: FakeTrash(), library: dir.appendingPathComponent("Library"), caskrooms: [],
                       spotlightConflict: { _ in spotlightOwns })
    }

    let running = FakeRunningApps([RunningApp(pid: 42, name: "Zed", path: "/Applications/Zed.app")])

    @Test func launcherHasKillQuitAndUninstallCommands() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let c = make(dir)
        #expect(c.launcher.results(for: "/").map(\.title) == ["/kill", "/quit", "/uninstall"])
        let row = try #require(c.launcher.results(for: "/kill zed").first)
        guard case .runCommand(let name, let argument) = row.action else { Issue.record("not a command"); return }
        _ = c.launcher.runCommand(name: name, argument: argument)
        #expect(running.forceQuit == [42])
    }

    @Test func startRegistersBothHotkeysAndWatchesApps() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let applier = FakeHotkeyApplier(); let watcher = FakeWatcher()
        let failures = make(dir, applier: applier, watcher: watcher).start()
        #expect(failures.isEmpty)
        #expect(applier.applied.map(\.1) == [.launcher, .clipboard])
        #expect(applier.applied.map(\.0) == [.defaultLauncher, .defaultClipboard])
        #expect(watcher.started)
    }

    @Test func startWithoutHotkeysOnlyWatches() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let applier = FakeHotkeyApplier(); let watcher = FakeWatcher()
        #expect(make(dir, applier: applier, watcher: watcher).start(registerHotkeys: false).isEmpty)
        #expect(applier.applied.isEmpty)
        #expect(watcher.started)
    }

    @Test func startReportsFailures() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let applier = FakeHotkeyApplier(); applier.error = .alreadyTaken
        let failures = make(dir, applier: applier).start()
        #expect(failures == [.launcher: .alreadyTaken, .clipboard: .alreadyTaken])
    }

    @Test func spotlightNoticeNeededOnlyWhenSpotlightOwnsHotkey() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        #expect(make(dir, spotlightOwns: true).needsSpotlightNotice)
        #expect(!make(dir, spotlightOwns: false).needsSpotlightNotice)
    }

    @Test func spotlightNoticeShownOnce() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let c = make(dir, spotlightOwns: true)
        c.markSpotlightNoticeShown()
        #expect(!c.needsSpotlightNotice)
        #expect(!make(dir, spotlightOwns: true).needsSpotlightNotice)
    }

    @Test func hotkeyRoutesToModel() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let c = make(dir)
        c.handleHotkey(.clipboard)
        #expect(c.model.isVisible && c.model.mode == .clipboard)
    }

    @Test func settingsLoadedFromDataDir() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        var s = Settings(); s.showMenuBarIcon = false
        try SettingsStore(fileURL: dir.appendingPathComponent("settings.json")).save(s)
        #expect(!make(dir).settings.showMenuBarIcon)
    }

    @Test func updateSettingsReplacesCurrent() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let c = make(dir)
        var s = c.settings; s.launchAtLogin = false
        c.updateSettings(s)
        #expect(!c.settings.launchAtLogin)
    }

    @Test func launcherSeesScannedApps() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        #expect(make(dir).launcher.results(for: "saf").map(\.title) == ["Safari"])
    }
}

@MainActor @Suite struct PanelMemoryTests {
    @Test func hidingReleasesRowsAndPreview() {
        let h = PanelHarness(); h.thumbnails = ClipThumbnails(clipboard: h.clipboard); h.start()
        h.pasteboard.copyText("hello"); h.clipboard.poll()
        h.model.hotkey(.clipboard)
        #expect(h.controller.preview.displayedText == "hello")
        h.model.hide()
        #expect(h.controller.tableView.numberOfRows == 0)
        #expect(h.controller.preview.displayedText == nil)
        h.model.hotkey(.clipboard)
        #expect(h.controller.displayedRowCount == 1)
    }
}
