import ServiceManagement

/// Launch at login via `SMAppService`. Only works from the bundled, signed app (verified in the smoke checklist).
public enum LoginItem {
    public static func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
}
