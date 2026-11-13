import AppKit

/// Borderless, non-activating floating panel: takes keyboard focus without stealing "frontmost app".
public final class HammerPanel: NSPanel {
    public var onResignKey: (() -> Void)?
    public var onKeyEquivalent: ((NSEvent) -> Bool)?

    public init(contentViewController: NSViewController) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Theme.launcherWidth, height: 300),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        self.contentViewController = contentViewController
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyEquivalent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}
