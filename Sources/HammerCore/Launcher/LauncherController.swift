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
    private let pasteboard: PasteboardAccess
    private let clock: HammerClock
    private var frecency: Frecency

    public init(search: LauncherSearch, store: FrecencyStore, launcher: AppLaunching, pasteboard: PasteboardAccess, clock: HammerClock) {
        self.search = search
        self.store = store
        self.launcher = launcher
        self.pasteboard = pasteboard
        self.clock = clock
        frecency = store.load()
    }

    /// A calculation's result first (when the query is one), then apps.
    public func results(for query: String) -> [LauncherResult] {
        let apps = search.search(query, frecency: frecency, now: clock.now())
        return Calculator.result(for: query).map { [$0] + apps } ?? apps
    }

    public func perform(_ result: LauncherResult) {
        switch result.action {
        case .openApp(let path):
            launcher.openApp(at: path)
        case .copyText(let text):
            pasteboard.write([Representation(type: PasteboardType.plainText, data: Data(text.utf8))])
            return   // not an app: no usage to record
        }
        frecency.recordUse(id: result.id, at: clock.now())
        do {
            try store.save(frecency)
        } catch {
            Self.log.error("Saving usage failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
