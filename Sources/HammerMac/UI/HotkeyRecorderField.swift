import AppKit
import HammerCore

/// Click, then press a key combination to record a hotkey. Esc cancels.
@MainActor public final class HotkeyRecorderField: NSView {
    public var hotkey: Hotkey? { didSet { needsDisplay = true } }
    public var onRecord: ((Hotkey) -> Void)?
    public private(set) var isRecording = false

    var displayText: String { isRecording ? "Press shortcut…" : (hotkey?.displayString ?? "Click to record") }

    public override var acceptsFirstResponder: Bool { true }
    public override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 24) }

    public func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func stopRecording() {
        isRecording = false
        needsDisplay = true
    }

    public override func mouseDown(with event: NSEvent) { startRecording() }

    public override func resignFirstResponder() -> Bool {
        stopRecording()
        return true
    }

    public override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        if event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            stopRecording()
            return
        }
        guard let hotkey = Self.hotkey(from: event) else { return }
        stopRecording()
        onRecord?(hotkey)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    public static func hotkey(from event: NSEvent) -> Hotkey? {
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags
        var modifiers: Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    public override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13),
                                                    .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor]
        let size = (displayText as NSString).size(withAttributes: attrs)
        (displayText as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }
}
