import Foundation
import Testing
import HammerCore
@testable import HammerMac

@Suite struct FileSystemAppScannerTests {
    func fixture() -> URL {
        let dir = makeTempDir()
        makeFakeApp("Foo", in: dir, bundleID: "com.test.foo")
        let sub = dir.appendingPathComponent("Sub", isDirectory: true)
        try! FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        makeFakeApp("Bar", in: sub)
        makeFakeApp("Inner", in: dir.appendingPathComponent("Foo.app/Contents/Helpers", isDirectory: true))
        try! Data("x".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        return dir
    }

    @Test func findsAppsRecursively() {
        let dir = fixture(); defer { removeTempDir(dir) }
        #expect(FileSystemAppScanner(roots: [dir]).scan().map(\.name).sorted() == ["Bar", "Foo"])
    }

    @Test func doesNotDescendIntoBundles() {
        let dir = fixture(); defer { removeTempDir(dir) }
        #expect(!FileSystemAppScanner(roots: [dir]).scan().contains { $0.name == "Inner" })
    }

    @Test func readsBundleIDAndPath() {
        let dir = fixture(); defer { removeTempDir(dir) }
        let foo = FileSystemAppScanner(roots: [dir]).scan().first { $0.name == "Foo" }
        #expect(foo?.bundleID == "com.test.foo")
        #expect(foo?.path.hasSuffix("/Foo.app") == true)
        #expect(FileSystemAppScanner(roots: [dir]).scan().first { $0.name == "Bar" }?.bundleID == nil)
    }

    @Test func findsHiddenFlaggedSymlinkedApp() throws {
        // Like /Applications/Safari.app on macOS 13+: a symlink into the Cryptex with the BSD "hidden" flag.
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let elsewhere = makeTempDir(); defer { removeTempDir(elsewhere) }
        let target = makeFakeApp("Safari", in: elsewhere, bundleID: "com.apple.Safari")
        let link = dir.appendingPathComponent("Safari.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let chflags = Process()
        chflags.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        chflags.arguments = ["-h", "hidden", link.path]
        try chflags.run(); chflags.waitUntilExit()
        let found = FileSystemAppScanner(roots: [dir]).scan()
        #expect(found.map(\.name) == ["Safari"])
        #expect(found.first?.bundleID == "com.apple.Safari")
        #expect(found.first?.path.hasSuffix(dir.lastPathComponent + "/Safari.app") == true)  // the link, not its target
    }

    @Test func skipsDotNamedEntries() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        makeFakeApp(".Secret", in: dir)
        makeFakeApp("Visible", in: dir)
        #expect(FileSystemAppScanner(roots: [dir]).scan().map(\.name) == ["Visible"])
    }

    @Test func missingRootIsSkipped() {
        let dir = fixture(); defer { removeTempDir(dir) }
        let scanner = FileSystemAppScanner(roots: [dir.appendingPathComponent("missing"), dir])
        #expect(scanner.scan().count == 2)
    }

    @Test func defaultRootsMatchSpec() {
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        #expect(FileSystemAppScanner.defaultRoots.map(\.path) == ["/Applications", "/System/Applications", home])
    }
}
