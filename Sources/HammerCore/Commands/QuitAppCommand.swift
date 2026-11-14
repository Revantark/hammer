import Foundation

public struct RunningApp: Equatable, Sendable {
    public let pid: Int32
    public let name: String
    /// The app bundle.
    public let path: String

    public init(pid: Int32, name: String, path: String) {
        self.pid = pid
        self.name = name
        self.path = path
    }
}

/// The apps that are running and a way to quit them.
@MainActor public protocol RunningAppControlling: AnyObject {
    /// Apps you can see (Dock or menu bar), not Hammer, not helpers inside other apps.
    func runningApps() -> [RunningApp]
    /// Asks the app to quit; it can still ask to save or refuse.
    func quit(pid: Int32)
    /// Ends the app at once; unsaved work is lost.
    func forceQuit(pid: Int32)
    /// True once the app has exited; false if it's still running after `timeout`.
    func waitForExit(pid: Int32, timeout: Duration) async -> Bool
}

/// `/quit <app>` asks a running app to quit; `/kill <app>` force-quits it.
@MainActor public final class QuitAppCommand: HammerCommand {
    public let name: String
    public let summary: String
    public let argument = CommandArgumentKind.option
    public let optionsTitle = "Running Apps"
    public let actionLabel: String

    private let force: Bool
    private let apps: RunningAppControlling

    public init(force: Bool, apps: RunningAppControlling) {
        self.force = force
        self.apps = apps
        name = force ? "kill" : "quit"
        summary = force ? "Force quit an app" : "Quit an app"
        actionLabel = force ? "Force Quit" : "Quit"
    }

    public func options() -> [CommandOption] {
        apps.runningApps().map { CommandOption(id: String($0.pid), title: $0.name, iconPath: $0.path) }
    }

    public func run(_ argument: CommandArgument) -> CommandOutcome {
        guard case .option(let option) = argument, let pid = Int32(option.id) else { return .done }
        if force { apps.forceQuit(pid: pid) } else { apps.quit(pid: pid) }
        return .done
    }
}
