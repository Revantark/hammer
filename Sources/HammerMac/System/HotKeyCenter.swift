import Carbon
import HammerCore

public enum HotkeyRegistrationError: Error, Equatable {
    case alreadyTaken
    case failed(OSStatus)
}

/// Global hotkeys via Carbon `RegisterEventHotKey` (no permission needed).
@MainActor public final class HotKeyCenter {
    private static let signature: OSType = 0x484D_5252  // "HMRR"

    private var registrations: [HotkeyRole: (hotkey: Hotkey, ref: EventHotKeyRef)] = [:]
    private var handlerRef: EventHandlerRef?
    public var onPress: ((HotkeyRole) -> Void)?

    public init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            let role: HotkeyRole = id.id == 1 ? .launcher : .clipboard
            MainActor.assumeIsolated { center.onPress?(role) }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    public func registeredHotkey(for role: HotkeyRole) -> Hotkey? { registrations[role]?.hotkey }

    /// Registers `hotkey` for `role`. On failure the previous hotkey for the role stays active.
    public func register(_ hotkey: Hotkey, role: HotkeyRole) throws {
        if registrations[role]?.hotkey == hotkey { return }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: role == .launcher ? 1 : 2)
        let status = RegisterEventHotKey(hotkey.keyCode, Self.carbonModifiers(hotkey.modifiers), id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            throw status == OSStatus(eventHotKeyExistsErr) ? HotkeyRegistrationError.alreadyTaken : .failed(status)
        }
        unregister(role: role)
        registrations[role] = (hotkey, ref)
    }

    public func unregister(role: HotkeyRole) {
        guard let existing = registrations.removeValue(forKey: role) else { return }
        UnregisterEventHotKey(existing.ref)
    }

    public static func carbonModifiers(_ m: Modifiers) -> UInt32 {
        var result: UInt32 = 0
        if m.contains(.command) { result |= UInt32(cmdKey) }
        if m.contains(.option) { result |= UInt32(optionKey) }
        if m.contains(.control) { result |= UInt32(controlKey) }
        if m.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
