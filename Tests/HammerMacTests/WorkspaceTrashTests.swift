import Foundation
import Testing
@testable import HammerMac

/// The real Trash is never touched here; only the decisions around it.
@Suite struct WorkspaceTrashTests {
    @Test func permissionErrorsGoThroughFinder() {
        #expect(WorkspaceTrash.needsFinder(CocoaError(.fileWriteNoPermission)))
        #expect(WorkspaceTrash.needsFinder(NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
                                                   userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])))
        #expect(!WorkspaceTrash.needsFinder(CocoaError(.fileNoSuchFile)))
    }

    @Test func pathIsPassedAsAnArgumentNotScriptText() {
        let path = #"/Applications/Evil" & do shell script "x".app"#
        let args = WorkspaceTrash.finderArguments(path: path)
        #expect(args.last == path)
        #expect(!args.dropLast().joined().contains("Evil"))
    }
}
