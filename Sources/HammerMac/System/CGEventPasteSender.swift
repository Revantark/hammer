import ApplicationServices
import CoreGraphics
import HammerCore

/// Sends ⌘V to the frontmost app. Needs the Accessibility permission.
@MainActor public final class CGEventPasteSender: PasteSending {
    private static let vKeyCode: CGKeyCode = 9

    private let trustCheck: () -> Bool

    public init(isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        trustCheck = isTrusted
    }

    public var isTrusted: Bool { trustCheck() }

    public func sendPaste() {
        for event in Self.makePasteEvents() { event.post(tap: .cghidEventTap) }
    }

    public func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public static func makePasteEvents() -> [CGEvent] {
        let source = CGEventSource(stateID: .combinedSessionState)
        return [true, false].compactMap { down in
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: down)
            event?.flags = .maskCommand
            return event
        }
    }
}
