import AppKit
import HammerCore

/// Running apps from NSWorkspace.
@MainActor public final class WorkspaceRunningApps: RunningAppControlling {
    public init() {}

    public func runningApps() -> [RunningApp] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != me, !app.isTerminated, let url = app.bundleURL,
                  Self.isListed(path: url.path, policy: app.activationPolicy) else { return nil }
            return RunningApp(pid: app.processIdentifier, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent, path: url.path)
        }
    }

    public func quit(pid: Int32) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    public func forceQuit(pid: Int32) {
        NSRunningApplication(processIdentifier: pid)?.forceTerminate()
    }

    public func waitForExit(pid: Int32, timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return NSRunningApplication(processIdentifier: pid)?.isTerminated ?? true
    }

    /// Dock and menu bar apps whose bundle isn't nested inside another app (those are helpers).
    nonisolated static func isListed(path: String, policy: NSApplication.ActivationPolicy) -> Bool {
        guard policy == .regular || policy == .accessory, path.hasSuffix(".app") else { return false }
        return !path.dropLast(4).contains(".app/")
    }
}
