import AppKit
import Testing
import HammerCore
@testable import HammerMac

/// Holds a command's work until the test lets it finish.
@MainActor final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() { isOpen = true; waiters.forEach { $0.resume() }; waiters = [] }
}

func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                     characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
}
func spaceKey() -> NSEvent { key(49, " ") }
func returnKey() -> NSEvent { key(36, "\r") }
func escapeKey() -> NSEvent { key(53, "\u{1b}") }

@MainActor @Suite struct CommandFlowTests {
    final class Log { var confirmed: [[String]] = [] }

    struct Setup {
        let h: PanelHarness
        let log: Log
        let gate: Gate
        let kill: FakeCommand
    }

    func setup(note: String? = nil, items: [String] = ["/Applications/Zed.app", "~/Library/Caches/dev.zed.Zed"],
               report: CommandReport = CommandReport(succeeded: true, title: "Zed moved to the Trash", lines: ["2 items · 2 MB"])) -> Setup {
        let log = Log(), gate = Gate()
        let uninstall = FakeCommand("uninstall", actionLabel: "Uninstall")
        uninstall.choices = [appOption("Zed")]
        uninstall.outcome = .confirm(Checklist(title: "Uninstall Zed", note: note, confirmLabel: "Move to Trash", workingTitle: "Moving to the Trash…",
                                               items: items.map { ChecklistItem(path: $0, title: $0) },
                                               sizer: { $0.hasSuffix(".app") ? 2_000_000 : 3_000 }) { checked in
            log.confirmed.append(checked.map(\.path))
            await gate.wait()
            return report
        })
        let kill = FakeCommand("kill", actionLabel: "Force Quit")
        kill.choices = [appOption("Zed")]
        kill.outcome = .working(title: "Force quitting Zed…", keepsPanelOpen: false) {
            await gate.wait()
            return CommandReport(succeeded: true, title: "Zed was force quit", lines: [])
        }
        let h = PanelHarness(commands: [uninstall, kill]).start()
        h.model.hotkey(.launcher)
        return Setup(h: h, log: log, gate: gate, kill: kill)
    }

    func choose(_ s: Setup, _ query: String = "/uninstall zed") {
        s.h.type(query)
        s.h.controller.handleKey(.enter)
    }

    func cell(_ h: PanelHarness, row: Int) throws -> ItemCellView {
        try #require(h.controller.tableView(h.controller.tableView, viewFor: nil, row: row) as? ItemCellView)
    }

    func rowTitles(_ h: PanelHarness) -> [String] {
        (0..<h.controller.numberOfRows(in: h.controller.tableView)).compactMap { row in
            if let c = h.controller.tableView(h.controller.tableView, viewFor: nil, row: row) as? ItemCellView { return c.title.stringValue }
            return (h.controller.tableView(h.controller.tableView, viewFor: nil, row: row) as? HeaderCellView)?.label.stringValue
        }
    }

    // MARK: Lock

    @Test func choosingAnAppLocksOntoIt() async throws {
        let s = setup(); let h = s.h
        choose(s)
        #expect(h.model.isVisible)
        #expect(h.controller.searchField.stringValue == "Uninstall Zed")
        #expect(!h.controller.searchField.isEditable)
        #expect(h.controller.displayedHeaders == ["Uninstall Zed"])
        #expect(try cell(h, row: 1).title.stringValue == "/Applications/Zed.app")
        #expect(try cell(h, row: 1).iconView.image === PanelViewController.checkedGlyph)
        #expect(h.controller.footerRightText == "Move to Trash ↵  Toggle Space  Back esc")
        await h.controller.checklistSizes?.value
        #expect(try cell(h, row: 1).trailing.stringValue == "2 MB")
        #expect(h.controller.footerLeftText == "2 selected · 2 MB")
        #expect(s.log.confirmed.isEmpty)
    }

    @Test func typingDoesNothingWhileLocked() {
        let s = setup(); let h = s.h
        choose(s)
        #expect(h.controller.handleKeyDown(key(0, "a")))
        #expect(h.controller.handleKeyDown(key(51, "\u{7f}")))   // delete
        #expect(h.controller.searchField.stringValue == "Uninstall Zed")
        #expect(h.controller.displayedHeaders == ["Uninstall Zed"])
        #expect(!h.controller.handleKeyDown(key(43, ",", .command)))   // ⌘, still opens Settings
    }

    @Test func spaceTogglesTheSelectedItemOnly() throws {
        let s = setup(); let h = s.h
        choose(s)
        #expect(h.controller.handleKeyDown(key(125, "\u{F701}")))   // ↓
        #expect(h.controller.handleKeyDown(spaceKey()))
        #expect(try cell(h, row: 1).iconView.image === PanelViewController.checkedGlyph)
        #expect(try cell(h, row: 2).iconView.image === PanelViewController.uncheckedGlyph)
        #expect(h.controller.footerLeftText.hasPrefix("1 selected"))
    }

    @Test func keysTypeNormallyWhenNotLocked() {
        let s = setup()
        #expect(!s.h.controller.handleKeyDown(spaceKey()))
        #expect(!s.h.controller.handleKeyDown(key(0, "a")))
    }

    @Test func escapeUnlocksBackToTheList() {
        let s = setup(); let h = s.h
        choose(s)
        #expect(h.controller.handleKeyDown(escapeKey()))
        #expect(h.model.isVisible)
        #expect(h.controller.searchField.isEditable)
        #expect(h.controller.searchField.stringValue == "/uninstall zed")
        #expect(h.controller.displayedHeaders == ["Running Apps"])
        #expect(!h.controller.handleKeyDown(spaceKey()))
        #expect(s.log.confirmed.isEmpty)
    }

    @Test func noteShowsAboveTheItemsAndIsNotSelectable() throws {
        let s = setup(note: "Zed is running. Hammer will ask it to quit first."); let h = s.h
        choose(s)
        #expect(try cell(h, row: 1).title.stringValue == "Zed is running. Hammer will ask it to quit first.")
        #expect(h.controller.displayedRowCount == 2)
        #expect(try cell(h, row: 2).title.stringValue == "/Applications/Zed.app")
    }

    @Test func enterWithNothingTickedDoesNothing() {
        let s = setup(items: ["/Applications/Zed.app"]); let h = s.h
        choose(s)
        h.controller.handleKey(.toggle)
        h.controller.handleKey(.enter)
        #expect(h.controller.commandTask == nil)
        #expect(h.controller.displayedHeaders == ["Uninstall Zed"])
    }

    // MARK: Working → result

    @Test func enterShowsWorkingThenTheResult() async throws {
        let s = setup(); let h = s.h
        choose(s)
        h.controller.handleKey(.toggle)
        #expect(h.controller.handleKeyDown(returnKey()))
        #expect(rowTitles(h) == ["Moving to the Trash…"])
        #expect(h.controller.searchField.stringValue == "Uninstall Zed")
        #expect(h.controller.footerRightText == "Close esc")
        #expect(h.controller.handleKeyDown(returnKey()))   // ignored while working
        #expect(h.controller.handleKeyDown(spaceKey()))
        s.gate.open()
        await h.controller.commandTask?.value
        #expect(s.log.confirmed == [["~/Library/Caches/dev.zed.Zed"]])
        #expect(rowTitles(h) == ["Zed moved to the Trash", "2 items · 2 MB"])
        #expect(try cell(h, row: 0).iconView.image === PanelViewController.successGlyph)
        #expect(h.controller.footerRightText == "Open Launcher ↵  Close esc")
        #expect(h.controller.searchField.stringValue == "Uninstall Zed")
        #expect(!h.controller.searchField.isEditable)
    }

    @Test func failureShowsWhatWentWrong() async throws {
        let s = setup(report: CommandReport(succeeded: false, title: "Zed is still running", lines: ["Quit it, then try again."])); let h = s.h
        choose(s)
        h.controller.handleKey(.enter)
        s.gate.open()
        await h.controller.commandTask?.value
        #expect(rowTitles(h) == ["Zed is still running", "Quit it, then try again."])
        #expect(try cell(h, row: 0).iconView.image === PanelViewController.failureGlyph)
    }

    @Test func enterOnTheResultOpensThePlainLauncher() async {
        let s = setup(); let h = s.h
        choose(s)
        h.controller.handleKey(.enter)
        s.gate.open()
        await h.controller.commandTask?.value
        #expect(h.controller.handleKeyDown(returnKey()))
        #expect(h.model.isVisible)
        #expect(h.model.query == "")
        #expect(h.controller.searchField.stringValue == "")
        #expect(h.controller.searchField.isEditable)
        #expect(h.controller.displayedHeaders == ["Applications"])
        #expect(h.controller.footerRightText.hasPrefix("Open ↵"))
        #expect(!h.controller.handleKeyDown(spaceKey()))
    }

    @Test func escapeOnTheResultClosesThePanel() async {
        let s = setup(); let h = s.h
        choose(s)
        h.controller.handleKey(.enter)
        s.gate.open()
        await h.controller.commandTask?.value
        h.controller.handleKey(.escape)
        #expect(!h.model.isVisible)
        h.model.hotkey(.launcher)
        #expect(h.controller.displayedHeaders == ["Applications"])
        #expect(h.controller.searchField.isEditable)
    }

    @Test func killGoesStraightToWorkingThenTheResult() async {
        let s = setup(); let h = s.h
        choose(s, "/kill zed")
        #expect(rowTitles(h) == ["Force quitting Zed…"])
        #expect(h.controller.searchField.stringValue == "Force Quit Zed")
        #expect(!h.controller.holdsPanelOpen)
        s.gate.open()
        await h.controller.commandTask?.value
        #expect(rowTitles(h) == ["Zed was force quit"])
        h.controller.handleKey(.enter)
        #expect(h.controller.displayedHeaders == ["Applications"])
    }

    // MARK: Focus and closing

    @Test func uninstallKeepsThePanelUpThroughAPasswordPromptThenTakesFocusBack() async {
        let s = setup(); let h = s.h
        var focusRequests = 0
        h.controller.onNeedsFocus = { focusRequests += 1 }
        choose(s)
        h.controller.handleKey(.enter)
        #expect(h.controller.holdsPanelOpen)
        s.gate.open()
        await h.controller.commandTask?.value
        #expect(!h.controller.holdsPanelOpen)
        #expect(focusRequests == 1)
    }

    @Test func closingWhileWorkingDropsTheResult() async {
        let s = setup(); let h = s.h
        choose(s)
        h.controller.handleKey(.enter)
        h.controller.handleKey(.escape)
        #expect(!h.model.isVisible)
        #expect(!h.controller.holdsPanelOpen)
        h.model.hotkey(.launcher)
        s.gate.open()
        await h.controller.commandTask?.value
        #expect(h.controller.displayedHeaders == ["Applications"])
        #expect(h.controller.searchField.isEditable)
        #expect(s.log.confirmed.count == 1)   // the work itself still finished
    }

    @Test func closingThePanelUnlocksIt() {
        let s = setup(); let h = s.h
        choose(s)
        h.model.hide()
        h.model.hotkey(.launcher)
        #expect(h.controller.displayedHeaders == ["Applications"])
        #expect(h.controller.searchField.isEditable)
        #expect(!h.controller.handleKeyDown(spaceKey()))
    }

    @Test func homebrewChecklistConfirmsWithNothingToTick() async {
        let s = setup(note: "Zed was installed with Homebrew.", items: []); let h = s.h
        choose(s)
        #expect(h.controller.footerRightText == "Move to Trash ↵  Back esc")
        h.controller.handleKey(.enter)
        s.gate.open()
        await h.controller.commandTask?.value
        #expect(s.log.confirmed == [[]])
    }
}
