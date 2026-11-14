import Foundation
import Testing
@testable import HammerCore

@MainActor final class FakeCommand: HammerCommand {
    let name: String
    let summary: String
    let argument: CommandArgumentKind
    let optionsTitle = "Things"
    let actionLabel: String
    var choices: [CommandOption] = []
    private(set) var runs: [CommandArgument] = []
    var outcome: CommandOutcome = .done

    init(_ name: String, summary: String = "Does a thing", argument: CommandArgumentKind = .option, actionLabel: String = "Do") {
        self.name = name
        self.summary = summary
        self.argument = argument
        self.actionLabel = actionLabel
    }

    func options() -> [CommandOption] { choices }
    func run(_ argument: CommandArgument) -> CommandOutcome { runs.append(argument); return outcome }
}

func option(_ title: String) -> CommandOption {
    CommandOption(id: "/Applications/\(title).app", title: title, iconPath: "/Applications/\(title).app")
}

@Suite struct CommandQueryTests {
    let names = ["kill", "quit", "uninstall"]

    @Test(arguments: [
        ("/", CommandQuery.commands(filter: "")),
        ("/unin", .commands(filter: "unin")),
        ("/UNIN", .commands(filter: "unin")),
        ("/uninstall", .argument(name: "uninstall", text: "")),
        ("/Uninstall", .argument(name: "uninstall", text: "")),
        ("/uninstall ", .argument(name: "uninstall", text: "")),
        ("/uninstall ze", .argument(name: "uninstall", text: "ze")),
        ("/kill  google chrome ", .argument(name: "kill", text: "google chrome")),
        ("/nope zed", .commands(filter: "nope zed")),
    ])
    func parses(query: String, expected: CommandQuery) {
        #expect(CommandQuery.parse(query, commandNames: names) == expected)
    }

    @Test(arguments: ["", "kill", " /kill", "8/32", "safari"])
    func onlyQueriesStartingWithSlashAreCommands(query: String) {
        #expect(CommandQuery.parse(query, commandNames: names) == nil)
    }
}

@MainActor @Suite struct CommandRegistryTests {
    let kill = FakeCommand("kill", summary: "Force quit an app", actionLabel: "Force Quit")
    let quit = FakeCommand("quit", summary: "Quit an app", actionLabel: "Quit")
    let uninstall = FakeCommand("uninstall", summary: "Uninstall an app", actionLabel: "Uninstall")
    let lock = FakeCommand("lock", summary: "Lock the screen", argument: .none)
    let google = FakeCommand("google", summary: "Search Google", argument: .text, actionLabel: "Search Google for")

    var registry: CommandRegistry { CommandRegistry([uninstall, quit, kill, lock, google]) }

    @Test func notACommandQueryGivesNil() {
        #expect(registry.results(for: "saf") == nil)
        #expect(registry.results(for: "") == nil)
    }

    @Test func slashListsEveryCommandAToZ() throws {
        let results = try #require(registry.results(for: "/"))
        #expect(results.map(\.title) == ["/google", "/kill", "/lock", "/quit", "/uninstall"])
        #expect(results.map(\.typeLabel) == ["Search Google", "Force quit an app", "Lock the screen", "Quit an app", "Uninstall an app"])
        #expect(Set(results.map(\.section)) == [CommandRegistry.section])
    }

    @Test func typingFiltersCommands() throws {
        #expect(try #require(registry.results(for: "/unin")).map(\.title) == ["/uninstall"])
        #expect(try #require(registry.results(for: "/q")).map(\.title) == ["/quit"])
        #expect(try #require(registry.results(for: "/zzz")).isEmpty)
    }

    @Test func commandRowsCompleteOrRun() throws {
        let rows = try #require(registry.results(for: "/"))
        let byTitle = Dictionary(uniqueKeysWithValues: rows.map { ($0.title, $0.action) })
        #expect(byTitle["/kill"] == .completeCommand("kill"))
        #expect(byTitle["/google"] == .completeCommand("google"))
        #expect(byTitle["/lock"] == .runCommand(name: "lock", argument: .none))
    }

    @Test func exactCommandNameListsAllItsOptions() throws {
        uninstall.choices = [option("Zed"), option("Arc"), option("Slack")]
        let results = try #require(registry.results(for: "/uninstall"))
        #expect(results.map(\.title) == ["Arc", "Slack", "Zed"])
        #expect(results.allSatisfy { $0.typeLabel == "Uninstall" && $0.section == "Things" })
        #expect(results.first?.action == .runCommand(name: "uninstall", argument: .option(option("Arc"))))
    }

    @Test func argumentTextFiltersOptionsBestMatchFirst() throws {
        uninstall.choices = [option("Zed"), option("Visual Studio Code"), option("Xcode")]
        #expect(try #require(registry.results(for: "/uninstall ze")).map(\.title) == ["Zed"])
        #expect(try #require(registry.results(for: "/uninstall code")).map(\.title) == ["Visual Studio Code", "Xcode"])   // word prefix beats substring
        #expect(try #require(registry.results(for: "/uninstall qqq")).isEmpty)
    }

    @Test func noArgumentCommandShowsOneRunRow() throws {
        let results = try #require(registry.results(for: "/lock"))
        #expect(results.map(\.title) == ["/lock"])
        #expect(results.first?.action == .runCommand(name: "lock", argument: .none))
    }

    @Test func textCommandPassesWhateverWasTyped() throws {
        #expect(try #require(registry.results(for: "/google")).isEmpty)
        let results = try #require(registry.results(for: "/google  swift testing "))
        #expect(results.map(\.title) == ["swift testing"])
        #expect(results.first?.typeLabel == "Search Google for")
        #expect(results.first?.action == .runCommand(name: "google", argument: .text("swift testing")))
    }

    @Test func runFindsTheCommandByName() {
        let r = registry
        #expect(r.run(name: "kill", argument: .option(option("Zed"))) != nil)
        #expect(kill.runs == [.option(option("Zed"))])
        #expect(r.run(name: "missing", argument: .none) == nil)
    }
}
