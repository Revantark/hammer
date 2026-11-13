import AppKit
import HammerCore

/// Launches an app, or brings it to the front if already running.
@MainActor public final class WorkspaceAppLauncher: AppLaunching {
    private let open: @MainActor (URL) -> Void

    public init(open: @escaping @MainActor (URL) -> Void = { url in
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }) {
        self.open = open
    }

    public func openApp(at path: String) {
        open(URL(fileURLWithPath: path))
    }
}
