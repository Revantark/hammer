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

    @Test func killForceQuits() {
        let kill = QuitAppCommand(force: true, apps: running)
        #expect(kill.name == "kill")
        #expect(kill.actionLabel == "Force Quit")
        _ = kill.run(.option(kill.options()[0]))
        #expect(running.forceQuit == [101])
        #expect(running.quit.isEmpty)
    }

    @Test func quitAsksNicely() {
        let quit = QuitAppCommand(force: false, apps: running)
        #expect(quit.name == "quit")
        #expect(quit.actionLabel == "Quit")
        _ = quit.run(.option(quit.options()[1]))
        #expect(running.quit == [202])
        #expect(running.forceQuit.isEmpty)
    }

    @Test func runWithoutAnAppDoesNothing() {
        let kill = QuitAppCommand(force: true, apps: running)
        _ = kill.run(.none)
        _ = kill.run(.text("zed"))
        #expect(running.forceQuit.isEmpty)
    }

    @Test func typingFiltersRunningApps() {
        let registry = CommandRegistry([QuitAppCommand(force: true, apps: running)])
        #expect(registry.results(for: "/kill gh")?.map(\.title) == ["Ghostty"])
        #expect(registry.results(for: "/kill")?.map(\.title) == ["Ghostty", "Zed"])
        #expect(registry.results(for: "/kill")?.first?.section == "Running Apps")
    }
}
