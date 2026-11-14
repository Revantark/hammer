import AppKit
import Testing
import HammerCore
@testable import HammerMac

@MainActor @Suite struct CommandPanelTests {
    func harness() -> (PanelHarness, FakeCommand) {
        let kill = FakeCommand("kill", summary: "Force quit an app")
        kill.choices = [appOption("Zed"), appOption("Ghostty")]
        let h = PanelHarness(commands: [kill, FakeCommand("lock", summary: "Lock the screen", argument: .none)]).start()
        h.model.hotkey(.launcher)
        return (h, kill)
    }

    func cell(_ h: PanelHarness, row: Int) throws -> ItemCellView {
        try #require(h.controller.tableView(h.controller.tableView, viewFor: nil, row: row) as? ItemCellView)
    }

    @Test func slashListsCommandsWithTheirSummaries() throws {
        let (h, _) = harness()
        h.type("/")
        #expect(h.controller.displayedHeaders == [CommandRegistry.section])
        #expect(h.controller.displayedRowCount == 2)
        let first = try cell(h, row: 1)
        #expect(first.title.stringValue == "/kill")
        #expect(first.trailing.stringValue == "Force quit an app")
        #expect(first.iconView.image === PanelViewController.commandGlyph)
        #expect(h.controller.footerRightText.hasPrefix("Select ↵"))
    }

    @Test func enterOnACommandFillsItInAndShowsItsOptions() throws {
        let (h, kill) = harness()
        h.type("/ki")
        h.controller.handleKey(.enter)
        #expect(h.model.isVisible)
        #expect(h.controller.searchField.stringValue == "/kill ")
        #expect(h.model.query == "/kill ")
        #expect(h.controller.displayedHeaders == ["Running Apps"])
        #expect(try cell(h, row: 1).title.stringValue == "Ghostty")
        #expect(try cell(h, row: 1).trailing.stringValue == "Force Quit")
        #expect(h.controller.footerRightText.hasPrefix("Force Quit ↵"))
        #expect(kill.runs.isEmpty)
    }

    @Test func tabCompletesTheSelectedCommand() {
        let (h, _) = harness()
        h.type("/k")
        h.controller.handleKey(.tab)
        #expect(h.model.query == "/kill ")
    }

    @Test func tabOnAnAppRowDoesNothing() {
        let (h, _) = harness()
        h.type("saf")
        h.controller.handleKey(.tab)
        #expect(h.model.query == "saf")
        #expect(h.model.isVisible)
    }

    @Test func enterOnAnOptionRunsTheCommandAndCloses() {
        let (h, kill) = harness()
        h.type("/kill ze")
        h.controller.handleKey(.enter)
        #expect(kill.runs == [.option(appOption("Zed"))])
        #expect(!h.model.isVisible)
        #expect(h.appLauncher.opened.isEmpty)
    }

    @Test func optionRowsShowTheAppIcon() async throws {
        let (h, _) = harness()
        h.type("/kill")
        await h.controller.iconPrefetch?.value
        #expect(try cell(h, row: 1).iconPath == "/Applications/Ghostty.app")
        #expect(try cell(h, row: 1).iconView.image != nil)
    }

    @Test func commandWithoutArgumentRunsOnEnter() {
        let (h, _) = harness()
        h.type("/lo")
        #expect(h.controller.footerRightText.hasPrefix("Run ↵"))
        h.controller.handleKey(.enter)
        #expect(!h.model.isVisible)
    }

    @Test func placeholderMentionsCommands() {
        let (h, _) = harness()
        #expect(h.controller.searchField.placeholderAttributedString?.string == "Search apps, or / for commands…")
    }
}
