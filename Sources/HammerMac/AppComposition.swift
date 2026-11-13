import Foundation
import HammerCore

/// Builds and owns the app's model objects. AppKit glue lives in the app's delegate.
@MainActor public final class AppComposition {
    public let model = PanelModel()
    public let catalog: AppCatalog
    public let launcher: LauncherController
    public let clipboard: ClipboardController
    public let settingsStore: SettingsStore
    public let pasteSender: PasteSending
    public let clock: HammerClock
    public private(set) var settings: Settings

    private let hotkeys: HotkeyApplying
    private let watcher: DirectoryWatching
    private let spotlightConflict: (Hotkey) -> Bool

    public init(dataDirectory: URL, pasteboard: PasteboardAccess, scanner: AppScanning, watcher: DirectoryWatching,
                appLauncher: AppLaunching, pasteSender: PasteSending, hotkeys: HotkeyApplying, clock: HammerClock,
                spotlightConflict: @escaping (Hotkey) -> Bool = { SpotlightShortcut.conflicts(with: $0) }) {
        settingsStore = SettingsStore(fileURL: dataDirectory.appendingPathComponent("settings.json"))
        settings = settingsStore.load()
        catalog = AppCatalog(scanner: scanner)
        launcher = LauncherController(search: LauncherSearch(sources: [AppsSource(catalog: catalog)]),
                                      store: FrecencyStore(fileURL: dataDirectory.appendingPathComponent("frecency.json")),
                                      launcher: appLauncher, clock: clock)
        clipboard = ClipboardController(pasteboard: pasteboard, store: ClipStore(directory: dataDirectory), clock: clock)
        self.pasteSender = pasteSender
        self.clock = clock
        self.hotkeys = hotkeys
        self.watcher = watcher
        self.spotlightConflict = spotlightConflict
    }

    /// Registers hotkeys and starts watching app folders. Returns hotkeys that failed to register.
    public func start(registerHotkeys: Bool = true) -> [HotkeyRole: HotkeyRegistrationError] {
        var failures: [HotkeyRole: HotkeyRegistrationError] = [:]
        for role in [HotkeyRole.launcher, .clipboard] where registerHotkeys {
            do {
                try hotkeys.apply(settings.hotkey(for: role), role: role)
            } catch let error as HotkeyRegistrationError {
                failures[role] = error
            } catch {
                failures[role] = .failed(-1)
            }
        }
        catalog.startWatching(watcher)
        return failures
    }

    public func handleHotkey(_ role: HotkeyRole) {
        model.hotkey(role)
    }

    public var needsSpotlightNotice: Bool {
        !settings.didShowSpotlightNotice && spotlightConflict(settings.launcherHotkey)
    }

    public func markSpotlightNoticeShown() {
        settings.didShowSpotlightNotice = true
        try? settingsStore.save(settings)
    }

    public func updateSettings(_ new: Settings) {
        settings = new
    }
}
