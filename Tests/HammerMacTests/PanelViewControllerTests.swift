import AppKit
import Testing
import HammerCore
@testable import HammerMac

@MainActor @Suite struct PanelViewControllerTests {
    @Test func launcherShowsAllAppsOnEmptyQuery() {
        let h = PanelHarness().start(); h.model.hotkey(.launcher)
        #expect(h.controller.displayedRowCount == 3)
        #expect(h.controller.displayedHeaders == ["Applications"])
    }

    @Test func appIconsLoadOffTheMainThreadAndFillRows() async throws {
        let h = PanelHarness().start(); h.model.hotkey(.launcher)
        await h.controller.iconPrefetch?.value
        #expect(h.iconLoads.calls == 3)
        #expect(h.iconLoads.onMain == 0)
        let cell = try #require(h.controller.tableView.view(atColumn: 0, row: 1, makeIfNecessary: true) as? ItemCellView)
        #expect(cell.iconView.image != nil)
    }

    @Test func prefetchCoversOnlyTheFirstScreens() async {
        let h = PanelHarness(apps: (0..<40).map { app(String(format: "App%02d", $0)) }).start()
        h.model.hotkey(.launcher)
        await h.controller.iconPrefetch?.value
        #expect(h.iconLoads.calls == PanelViewController.iconPrefetchLimit)
    }

    @Test func reopeningUsesCachedIcons() async {
        let h = PanelHarness().start(); h.model.hotkey(.launcher)
        await h.controller.iconPrefetch?.value
        h.model.hide(); h.model.hotkey(.launcher)
        await h.controller.iconPrefetch?.value
        #expect(h.iconLoads.calls == 3)
    }

    @Test func recentlyOpenedAppListedFirstUnderRecent() {
        let h = PanelHarness().start(); h.model.hotkey(.launcher)
        h.type("sla"); h.controller.handleKey(.enter)
        h.model.hotkey(.launcher)
        #expect(h.controller.displayedHeaders == ["Recent", "Applications"])
        #expect(h.controller.displayedRowCount == 3)
        h.controller.handleKey(.enter)
        #expect(h.appLauncher.opened.count == 2)
        #expect(h.appLauncher.opened[1] == h.appLauncher.opened[0])
    }

    @Test func typingFiltersRows() {
        let h = PanelHarness().start(); h.model.hotkey(.launcher)
        h.type("saf")
        #expect(h.controller.displayedRowCount == 1)
        #expect(h.model.query == "saf")
    }

    @Test func downThenEnterLaunchesSecond() {
        let h = PanelHarness().start(); h.model.hotkey(.launcher)
        let second = h.launcher.results(for: "")[1]
        h.controller.handleKey(.down)
        h.controller.handleKey(.enter)
        #expect(h.appLauncher.opened == [second.id])
        #expect(!h.model.isVisible)
    }

    @Test func calculationShowsFirstAndEnterCopiesIt() throws {
        let h = PanelHarness().start(); h.model.hotkey(.launcher)
        h.type("8(5+3*2+(4*2 + 5 - 10)/2)")
        #expect(h.controller.displayedHeaders.first == Calculator.section)
        let cell = try #require(h.controller.tableView(h.controller.tableView, viewFor: nil, row: 1) as? ItemCellView)
        #expect(cell.title.stringValue == "100")
        #expect(cell.iconView.image === PanelViewController.calculatorGlyph)
        h.controller.handleKey(.enter)
        #expect(h.pasteboard.written.last == [Representation(type: PasteboardType.plainText, data: Data("100".utf8))])
        #expect(h.appLauncher.opened.isEmpty)
        #expect(!h.model.isVisible)
    }

    @Test func footerSaysCopyWhileACalculationIsSelected() {
        let h = PanelHarness().start(); h.model.hotkey(.launcher)
        h.type("4/10")
        #expect(h.controller.footerRightText.hasPrefix("Copy ↵"))
        h.type("saf")
        #expect(h.controller.footerRightText.hasPrefix("Open ↵"))
    }

    @Test func enterWithNoResultsDoesNothing() {
        let h = PanelHarness().start(); h.model.hotkey(.launcher)
        h.type("zzzz")
        h.controller.handleKey(.enter)
        #expect(h.appLauncher.opened.isEmpty)
        #expect(h.model.isVisible)
    }

    @Test func escapeHides() {
        let h = PanelHarness().start(); h.model.hotkey(.launcher)
        h.controller.handleKey(.escape)
        #expect(!h.model.isVisible)
    }

    @Test func reopeningClearsSearchField() {
        let h = PanelHarness().start(); h.model.hotkey(.launcher)
        h.type("saf"); h.model.hide(); h.model.hotkey(.launcher)
        #expect(h.controller.searchField.stringValue == "")
        #expect(h.controller.displayedRowCount == 3)
    }

    @Test func footerTextLauncher() {
        let h = PanelHarness().start(); h.model.hotkey(.launcher)
        #expect(h.controller.footerLeftText == "Hammer")
    }

    @Test func footerShowsCurrentHotkeys() {
        let h = PanelHarness().start()
        h.settings.clipboardHotkey = Hotkey(keyCode: 9, modifiers: [.control, .option])
        h.model.hotkey(.launcher)
        #expect(h.controller.footerRightText.contains("⌃⌥V"))
    }

    @Test func cmdCommaOpensSettings() {
        let h = PanelHarness().start(); h.model.hotkey(.launcher)
        var opened = 0
        h.controller.onOpenSettings = { opened += 1 }
        h.controller.handleKey(.openSettings)
        #expect(opened == 1)
    }

    @Test func keyCommandMapping() {
        func key(_ chars: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                             context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 43)!
        }
        #expect(PanelKeyCommand.from(key(",", .command)) == .openSettings)
        #expect(PanelKeyCommand.from(key(",", [])) == nil)
    }

    @Test func visibilityCallbackFires() {
        let h = PanelHarness().start()
        var states: [Bool] = []
        h.controller.onVisibilityChanged = { states.append($0) }
        h.model.hotkey(.launcher); h.model.setQuery("a"); h.model.hide()
        #expect(states == [true, false])
    }

    @Test func launcherPanelSizeFollowsRows() {
        let h = PanelHarness().start(); h.model.hotkey(.launcher)
        let full = h.controller.preferredPanelSize
        h.type("saf")
        #expect(h.controller.preferredPanelSize.width == Theme.launcherWidth)
        #expect(h.controller.preferredPanelSize.height < full.height)
    }
}

@MainActor @Suite struct ItemCellLayoutTests {
    func laidOut(_ trailing: String, title: String = "Safari") -> ItemCellView {
        let cell = ItemCellView(frame: NSRect(x: 0, y: 0, width: 600, height: Theme.rowHeight))
        cell.title.stringValue = title
        cell.trailing.stringValue = trailing
        cell.layout()
        return cell
    }

    func fullWidth(_ label: NSTextField) -> CGFloat {
        ceil((label.stringValue as NSString).size(withAttributes: [.font: label.font!]).width)
    }

    @Test(arguments: ["Application", "Copy"])
    func trailingLabelIsNeverCut(_ text: String) {
        let cell = laidOut(text)
        #expect(cell.trailing.frame.width >= fullWidth(cell.trailing))
    }

    @Test func reusedCellFitsItsNewLabel() {
        let cell = laidOut("Application")
        cell.trailing.stringValue = "Copy"
        cell.layout()
        cell.trailing.stringValue = "Application"
        cell.layout()
        #expect(cell.trailing.frame.width >= fullWidth(cell.trailing))
    }
}
