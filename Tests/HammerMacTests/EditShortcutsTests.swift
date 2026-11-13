import AppKit
import Testing
@testable import HammerMac

@MainActor @Suite struct EditShortcutsTests {
    func key(_ chars: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 0)!
    }

    @Test func standardEditingShortcutsMapToActions() {
        #expect(EditShortcuts.action(for: key("v", .command)) == #selector(NSText.paste(_:)))
        #expect(EditShortcuts.action(for: key("c", .command)) == #selector(NSText.copy(_:)))
        #expect(EditShortcuts.action(for: key("x", .command)) == #selector(NSText.cut(_:)))
        #expect(EditShortcuts.action(for: key("a", .command)) == #selector(NSText.selectAll(_:)))
        #expect(EditShortcuts.action(for: key("z", .command)) == Selector(("undo:")))
        #expect(EditShortcuts.action(for: key("z", [.command, .shift])) == Selector(("redo:")))
    }

    @Test func otherKeysAreIgnored() {
        #expect(EditShortcuts.action(for: key("v", [])) == nil)
        #expect(EditShortcuts.action(for: key("v", [.command, .option])) == nil)
        #expect(EditShortcuts.action(for: key(",", .command)) == nil)
    }

    @Test func selectAllReachesSearchFieldInPanel() throws {
        let field = NSTextField(string: "hello world")
        let vc = NSViewController(); vc.view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        field.frame = NSRect(x: 0, y: 0, width: 200, height: 24); vc.view.addSubview(field)
        let panel = HammerPanel(contentViewController: vc)
        panel.makeFirstResponder(field)
        let editor = try #require(panel.firstResponder as? NSTextView)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(panel.performKeyEquivalent(with: key("a", .command)))
        #expect(editor.selectedRange() == NSRange(location: 0, length: 11))
    }
}
