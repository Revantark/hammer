import Foundation
import os

/// Launches or brings an app to the front.
@MainActor public protocol AppLaunching: AnyObject {
    func openApp(at path: String)
}

@MainActor public final class LauncherController {
    private static let log = Logger(subsystem: "dev.hammer", category: "launcher")

    private let search: LauncherSearch
    private let store: FrecencyStore
    private let launcher: AppLaunching
    private let clock: HammerClock
    private var frecency: Frecency

    public init(search: LauncherSearch, store: FrecencyStore, launcher: AppLaunching, clock: HammerClock) {
        self.search = search
        self.store = store
        self.launcher = launcher
        self.clock = clock
        frecency = store.load()
    }

    public func results(for query: String) -> [LauncherResult] {
        search.search(query, frecency: frecency, now: clock.now())
    }

    public func perform(_ result: LauncherResult) {
        switch result.action {
        case .openApp(let path):
            launcher.openApp(at: path)
        }
        frecency.recordUse(id: result.id, at: clock.now())
        do {
            try store.save(frecency)
        } catch {
            Self.log.error("Saving usage failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
