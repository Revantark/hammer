import CoreGraphics
import Foundation
import Testing
@testable import HammerMac

@MainActor @Suite struct WorkspaceAppLauncherTests {
    @Test func opensAppURL() {
        var opened: [URL] = []
        WorkspaceAppLauncher(open: { opened.append($0) }).openApp(at: "/Applications/Safari.app")
        #expect(opened == [URL(fileURLWithPath: "/Applications/Safari.app")])
    }
}

@MainActor @Suite struct CGEventPasteSenderTests {
    @Test func pasteEventsAreCommandV() {
        let events = CGEventPasteSender.makePasteEvents()
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == 9 })
        #expect(events.allSatisfy { $0.flags.contains(.maskCommand) })
        #expect(events[0].type == .keyDown && events[1].type == .keyUp)
    }

    @Test func trustReflectsInjectedCheck() {
        #expect(CGEventPasteSender(isTrusted: { true }).isTrusted)
        #expect(!CGEventPasteSender(isTrusted: { false }).isTrusted)
    }
}
