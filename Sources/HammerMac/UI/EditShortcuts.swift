import AppKit

/// Hammer has no main menu (it's a background app), so ⌘X/⌘C/⌘V/⌘A/⌘Z/⇧⌘Z would go nowhere.
/// The panel routes them to the first responder (the search field's editor) directly.
enum EditShortcuts {
    static func action(for event: NSEvent) -> Selector? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        if flags == [.command, .shift], key == "z" { return Selector(("redo:")) }
        guard flags == .command else { return nil }
        switch key {
        case "x": return #selector(NSText.cut(_:))
        case "c": return #selector(NSText.copy(_:))
        case "v": return #selector(NSText.paste(_:))
        case "a": return #selector(NSText.selectAll(_:))
        case "z": return Selector(("undo:"))
        default: return nil
        }
    }
}
