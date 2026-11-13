import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public var launcherHotkey = Hotkey.defaultLauncher
    public var clipboardHotkey = Hotkey.defaultClipboard
    public var launchAtLogin = true
    public var showMenuBarIcon = true
    public var didShowSpotlightNotice = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        launcherHotkey = try c.decodeIfPresent(Hotkey.self, forKey: .launcherHotkey) ?? d.launcherHotkey
        clipboardHotkey = try c.decodeIfPresent(Hotkey.self, forKey: .clipboardHotkey) ?? d.clipboardHotkey
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? d.showMenuBarIcon
        didShowSpotlightNotice = try c.decodeIfPresent(Bool.self, forKey: .didShowSpotlightNotice) ?? d.didShowSpotlightNotice
    }

    public func hotkey(for role: HotkeyRole) -> Hotkey {
        role == .launcher ? launcherHotkey : clipboardHotkey
    }

    public mutating func setHotkey(_ hotkey: Hotkey, for role: HotkeyRole) {
        if role == .launcher { launcherHotkey = hotkey } else { clipboardHotkey = hotkey }
    }

    /// Returns why `hotkey` can't be used for `role`, or nil if it's fine.
    public func validate(_ hotkey: Hotkey, for role: HotkeyRole) -> HotkeyValidationError? {
        if Hotkey.keyName(for: hotkey.keyCode) == nil { return .unknownKey }
        if hotkey.modifiers.isDisjoint(with: [.command, .option, .control]) { return .needsModifier }
        let other = role == .launcher ? clipboardHotkey : launcherHotkey
        if hotkey == other { return .sameAsOther }
        return nil
    }
}

public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Missing or corrupt → defaults.
    public func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL) else { return Settings() }
        return (try? JSONDecoder().decode(Settings.self, from: data)) ?? Settings()
    }

    public func save(_ settings: Settings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
    }
}
