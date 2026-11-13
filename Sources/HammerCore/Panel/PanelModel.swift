import Foundation

public enum PanelMode: Sendable {
    case launcher, clipboard
}

/// Panel state machine: visibility, mode, query and selection.
@MainActor public final class PanelModel {
    public private(set) var isVisible = false
    public private(set) var mode: PanelMode = .launcher
    public private(set) var query = ""
    public private(set) var selectedIndex = 0
    public var onChange: (() -> Void)?

    public init() {}

    /// Hidden → open in that mode. Open in same mode → hide. Open in other mode → switch.
    public func hotkey(_ role: HotkeyRole) {
        let target: PanelMode = role == .launcher ? .launcher : .clipboard
        if isVisible && mode == target {
            hide()
            return
        }
        mode = target
        isVisible = true
        query = ""
        selectedIndex = 0
        onChange?()
    }

    public func hide() {
        guard isVisible else { return }
        isVisible = false
        onChange?()
    }

    public func setQuery(_ q: String) {
        query = q
        selectedIndex = 0
        onChange?()
    }

    public func moveSelection(by delta: Int, count: Int) {
        selectedIndex = count > 0 ? min(max(selectedIndex + delta, 0), count - 1) : 0
        onChange?()
    }

    /// Keeps the selection on the same item id when the list changes underneath it.
    public func itemsChanged(newIDs: [String], oldIDs: [String]) {
        if selectedIndex < oldIDs.count, let index = newIDs.firstIndex(of: oldIDs[selectedIndex]) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }
        onChange?()
    }
}
