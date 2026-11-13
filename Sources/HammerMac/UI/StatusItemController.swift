import AppKit

/// Menu bar hammer icon with "Settings…" and "Quit Hammer".
@MainActor public final class StatusItemController: NSObject {
    private let item: NSStatusItem
    let menu = NSMenu()
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    public init(onSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onSettings = onSettings
        self.onQuit = onQuit
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        let image = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: "Hammer")
        image?.isTemplate = true
        item.button?.image = image
        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        let quit = NSMenuItem(title: "Quit Hammer", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.items = [settings, .separator(), quit]
        item.menu = menu
    }

    public var isVisible: Bool {
        get { item.isVisible }
        set { item.isVisible = newValue }
    }

    public var menuItemTitles: [String] { menu.items.filter { !$0.isSeparatorItem }.map(\.title) }

    public func remove() { NSStatusBar.system.removeStatusItem(item) }

    @objc private func settingsClicked() { onSettings() }
    @objc private func quitClicked() { onQuit() }
}
