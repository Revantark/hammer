import Foundation
import HammerCore

/// Detects whether Spotlight's own shortcut (symbolic hotkey 64) would swallow Hammer's launcher hotkey.
/// Registration doesn't fail when Spotlight owns ⌘Space, so we read Spotlight's setting instead.
public enum SpotlightShortcut {
    static let spotlightKey = "64"

    public static func readSymbolicHotkeys() -> [String: Any]? {
        UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
    }

    public static func conflicts(with hotkey: Hotkey, symbolicHotkeys: [String: Any]? = readSymbolicHotkeys()) -> Bool {
        guard let entry = symbolicHotkeys?[spotlightKey] as? [String: Any] else {
            return hotkey == .defaultLauncher   // not customized: Spotlight owns ⌘Space
        }
        let enabled = (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int).map { $0 != 0 } ?? true)
        guard enabled,
              let value = entry["value"] as? [String: Any],
              let params = value["parameters"] as? [Int], params.count >= 3 else { return false }
        return UInt32(params[1]) == hotkey.keyCode && modifiers(fromEventFlags: params[2]) == hotkey.modifiers
    }

    /// NSEvent.ModifierFlags raw values as stored in symbolic hotkeys.
    static func modifiers(fromEventFlags flags: Int) -> Modifiers {
        var m: Modifiers = []
        if flags & (1 << 20) != 0 { m.insert(.command) }
        if flags & (1 << 19) != 0 { m.insert(.option) }
        if flags & (1 << 18) != 0 { m.insert(.control) }
        if flags & (1 << 17) != 0 { m.insert(.shift) }
        return m
    }
}
