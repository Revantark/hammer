import AppKit
import Testing
import HammerCore
@testable import HammerMac

@MainActor @Suite struct ChecklistPanelTests {
    final class Log { var confirmed: [[String]] = [] }

    func harness(note: String? = nil, items: [String] = ["/Applications/Zed.app", "~/Library/Caches/dev.zed.Zed"]) -> (PanelHarness, Log) {
        let log = Log()
        let uninstall = FakeCommand("uninstall", actionLabel: "Uninstall")
        uninstall.choices = [appOption("Zed")]
        uninstall.outcome = .confirm(Checklist(title: "Uninstall Zed", note: note, confirmLabel: "Move to Trash",
                                               items: items.map { ChecklistItem(path: $0, title: $0) },
                                               sizer: { $0.hasSuffix(".app") ? 2_000_000 : 3_000 }) { checked in
            log.confirmed.append(checked.map(\.path))
            return "Moved \(checked.count) items to the Trash."
        })
        let h = PanelHarness(commands: [uninstall]).start()
        h.model.hotkey(.launcher)
        h.type("/uninstall zed")
        h.controller.handleKey(.enter)
        return (h, log)
    }

    func cell(_ h: PanelHarness, row: Int) throws -> ItemCellView {
        try #require(h.controller.tableView(h.controller.tableView, viewFor: nil, row: row) as? ItemCellView)
    }

    @Test func choosingAnAppShowsItsChecklist() async throws {
        let (h, log) = harness()
        #expect(h.model.isVisible)
        #expect(h.controller.displayedHeaders == ["Uninstall Zed"])
        #expect(h.controller.displayedRowCount == 2)
        #expect(try cell(h, row: 1).title.stringValue == "/Applications/Zed.app")
        #expect(try cell(h, row: 1).iconView.image === PanelViewController.checkedGlyph)
        #expect(h.controller.footerRightText == "Move to Trash ↵  Toggle Space  Back esc")
        await h.controller.checklistSizes?.value
        #expect(try cell(h, row: 1).trailing.stringValue == "2 MB")
        #expect(h.controller.footerLeftText == "2 selected · 2 MB")
        #expect(log.confirmed.isEmpty)
    }

    @Test func spaceTogglesTheSelectedItemOnly() throws {
        let (h, _) = harness()
        h.controller.handleKey(.down)
        #expect(h.controller.handleKeyDown(spaceKey()))
        #expect(try cell(h, row: 1).iconView.image === PanelViewController.checkedGlyph)
        #expect(try cell(h, row: 2).iconView.image === PanelViewController.uncheckedGlyph)
        #expect(h.controller.footerLeftText.hasPrefix("1 selected"))
    }

    @Test func spaceTypesNormallyOutsideAChecklist() {
        let h = PanelHarness().start()
        h.model.hotkey(.launcher)
        #expect(!h.controller.handleKeyDown(spaceKey()))
    }

    @Test func enterMovesTickedItemsAndShowsWhatHappened() async {
        let (h, log) = harness()
        h.controller.handleKey(.toggle)
        h.controller.handleKey(.enter)
        await h.controller.checklistTask?.value
        #expect(log.confirmed == [["~/Library/Caches/dev.zed.Zed"]])
        #expect(h.model.isVisible)
        #expect(h.model.query == "/uninstall ")
        #expect(h.controller.displayedHeaders == ["Running Apps"])
        #expect(h.controller.footerLeftText == "Moved 1 items to the Trash.")
        h.type("/uninstall z")
        #expect(h.controller.footerLeftText == "Hammer")
    }

    @Test func escapeGoesBackToTheListInsteadOfClosing() {
        let (h, log) = harness()
        h.controller.handleKey(.escape)
        #expect(h.model.isVisible)
        #expect(h.controller.displayedHeaders == ["Running Apps"])
        #expect(h.controller.searchField.stringValue == "/uninstall zed")
        #expect(!h.controller.handleKeyDown(spaceKey()))
        #expect(log.confirmed.isEmpty)
    }

    @Test func typingLeavesTheChecklist() {
        let (h, _) = harness()
        h.type("/uninstall ze")
        #expect(h.controller.displayedHeaders == ["Running Apps"])
    }

    @Test func closingThePanelDropsTheChecklist() {
        let (h, _) = harness()
        h.model.hide()
        h.model.hotkey(.launcher)
        #expect(h.controller.displayedHeaders == ["Applications"])
        #expect(!h.controller.handleKeyDown(spaceKey()))
    }

    @Test func noteShowsAboveTheItems() throws {
        let (h, _) = harness(note: "Zed is running. Hammer will ask it to quit first.")
        #expect(try cell(h, row: 1).title.stringValue == "Zed is running. Hammer will ask it to quit first.")
        #expect(h.controller.displayedRowCount == 2)   // the note isn't selectable
        #expect(try cell(h, row: 2).title.stringValue == "/Applications/Zed.app")
    }

    @Test func checklistWithNothingToTickConfirmsOnEnter() async {
        let (h, log) = harness(note: "Zed was installed with Homebrew.", items: [])
        #expect(h.controller.footerRightText == "Move to Trash ↵  Back esc")
        h.controller.handleKey(.enter)
        await h.controller.checklistTask?.value
        #expect(log.confirmed == [[]])
    }
}

func spaceKey() -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                     characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
}
