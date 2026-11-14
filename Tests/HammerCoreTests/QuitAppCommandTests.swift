import Foundation
import Testing
@testable import HammerCore

@MainActor final class FakeRunningApps: RunningAppControlling {
    var apps: [RunningApp]
    private(set) var quit: [Int32] = []
    private(set) var forceQuit: [Int32] = []
    var exitsWhenAsked = true

    init(_ apps: [RunningApp]) { self.apps = apps }

    func runningApps() -> [RunningApp] { apps }
    func quit(pid: Int32) { quit.append(pid); if exitsWhenAsked { apps.removeAll { $0.pid == pid } } }
    func forceQuit(pid: Int32) { forceQuit.append(pid); apps.removeAll { $0.pid == pid } }
    func waitForExit(pid: Int32, timeout: Duration) async -> Bool { !apps.contains { $0.pid == pid } }
}

@MainActor @Suite struct QuitAppCommandTests {
    let running = FakeRunningApps([RunningApp(pid: 101, name: "Zed", path: "/Applications/Zed.app"),
                                   RunningApp(pid: 202, name: "Ghostty", path: "/Applications/Ghostty.app")])

    @Test func optionsAreTheRunningApps() {
        let kill = QuitAppCommand(force: true, apps: running)
        #expect(kill.options() == [CommandOption(id: "101", title: "Zed", iconPath: "/Applications/Zed.app"),
                                   CommandOption(id: "202", title: "Ghostty", iconPath: "/Applications/Ghostty.app")])
    }

    func work(_ outcome: CommandOutcome) async throws -> (title: String, keepsOpen: Bool, report: CommandReport) {
        guard case .working(let title, let keepsOpen, let work) = outcome else { throw CancellationError() }
        return (title, keepsOpen, await work())
    }

    @Test func killForceQuitsAndReports() async throws {
        let kill = QuitAppCommand(force: true, apps: running)
        #expect(kill.name == "kill")
        #expect(kill.actionLabel == "Force Quit")
        let result = try await work(kill.run(.option(kill.options()[0])))
        #expect(result.title == "Force quitting Zed…")
        #expect(!result.keepsOpen)
        #expect(result.report == CommandReport(succeeded: true, title: "Zed was force quit", lines: []))
        #expect(running.forceQuit == [101])
        #expect(running.quit.isEmpty)
    }

    @Test func quitAsksNicelyAndReports() async throws {
        let quit = QuitAppCommand(force: false, apps: running)
        #expect(quit.name == "quit")
        #expect(quit.actionLabel == "Quit")
        let result = try await work(quit.run(.option(quit.options()[1])))
        #expect(result.title == "Quitting Ghostty…")
        #expect(result.report == CommandReport(succeeded: true, title: "Ghostty quit", lines: []))
        #expect(running.quit == [202])
        #expect(running.forceQuit.isEmpty)
    }

    @Test func appThatStaysOpenIsReported() async throws {
        running.exitsWhenAsked = false
        let quit = QuitAppCommand(force: false, apps: running)
        let result = try await work(quit.run(.option(quit.options()[0])))
        #expect(result.report == CommandReport(succeeded: false, title: "Zed is still open", lines: ["It may be asking you to save changes."]))
    }

    @Test func runWithoutAnAppDoesNothing() {
        let kill = QuitAppCommand(force: true, apps: running)
        guard case .done = kill.run(.none), case .done = kill.run(.text("zed")) else { Issue.record("should do nothing"); return }
        #expect(running.forceQuit.isEmpty)
    }

    @Test func typingFiltersRunningApps() {
        let registry = CommandRegistry([QuitAppCommand(force: true, apps: running)])
        #expect(registry.results(for: "/kill gh")?.map(\.title) == ["Ghostty"])
        #expect(registry.results(for: "/kill")?.map(\.title) == ["Ghostty", "Zed"])
        #expect(registry.results(for: "/kill")?.first?.section == "Running Apps")
    }
}
