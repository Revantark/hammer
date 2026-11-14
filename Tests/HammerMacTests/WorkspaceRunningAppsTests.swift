import AppKit
import Testing
@testable import HammerMac

@Suite struct WorkspaceRunningAppsTests {
    @Test(arguments: [
        ("/Applications/Zed.app", NSApplication.ActivationPolicy.regular, true),
        ("/Applications/Stats.app", .accessory, true),                                                     // menu bar app
        ("/Applications/Zed.app/Contents/MacOS/cli.app", .accessory, false),                               // helper inside an app
        ("/Applications/Google Chrome.app/Contents/Frameworks/Helper.app", .regular, false),
        ("/System/Library/CoreServices/Finder.app", .regular, true),
        ("/usr/libexec/agent", .regular, false),                                                           // not an app bundle
        ("/Applications/Thing.app", .prohibited, false),                                                   // background-only
    ])
    func listsOnlyTopLevelAppsYouCanSee(path: String, policy: NSApplication.ActivationPolicy, listed: Bool) {
        #expect(WorkspaceRunningApps.isListed(path: path, policy: policy) == listed)
    }
}
