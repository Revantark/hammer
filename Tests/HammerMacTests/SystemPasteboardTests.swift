import AppKit
import Testing
import HammerCore
@testable import HammerMac

@MainActor @Suite struct SystemPasteboardTests {
    func withPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
        let pb = NSPasteboard(name: .init("hammer-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        try body(pb)
    }

    @Test func writeThenSnapshotRoundTrips() {
        withPasteboard { pb in
            let sys = SystemPasteboard(pasteboard: pb, frontmostAppName: { "TestApp" })
            let reps = [Representation(type: PasteboardType.plainText, data: Data("hi".utf8)),
                        Representation(type: PasteboardType.rtf, data: Data("{\\rtf1 hi}".utf8))]
            sys.write(reps)
            #expect(Set(sys.snapshot().representations.map(\.type)) == Set(reps.map(\.type)))
            #expect(sys.snapshot().representations.first { $0.type == PasteboardType.plainText }?.data == Data("hi".utf8))
        }
    }

    @Test func snapshotSkipsUninterestingTypes() {
        withPasteboard { pb in
            pb.clearContents()
            pb.setString("x", forType: .string)
            pb.setData(Data("junk".utf8), forType: .init("com.example.private"))
            let types = SystemPasteboard(pasteboard: pb).snapshot().representations.map(\.type)
            #expect(types == [PasteboardType.plainText])
        }
    }

    @Test func snapshotKeepsFileURLForSkipping() {
        withPasteboard { pb in
            pb.clearContents()
            pb.writeObjects([URL(fileURLWithPath: "/tmp/a.txt") as NSURL])
            #expect(SystemPasteboard(pasteboard: pb).snapshot().representations.contains { $0.type == PasteboardType.fileURL })
        }
    }

    @Test func changeCountIncreasesOnWrite() {
        withPasteboard { pb in
            let sys = SystemPasteboard(pasteboard: pb)
            let before = sys.changeCount
            sys.write([Representation(type: PasteboardType.plainText, data: Data("a".utf8))])
            #expect(sys.changeCount > before)
        }
    }

    @Test func writeReturnsNewChangeCount() {
        withPasteboard { pb in
            let sys = SystemPasteboard(pasteboard: pb)
            let returned = sys.write([Representation(type: PasteboardType.plainText, data: Data("a".utf8))])
            #expect(returned == pb.changeCount)
        }
    }

    @Test func snapshotIncludesSourceApp() {
        withPasteboard { pb in
            #expect(SystemPasteboard(pasteboard: pb, frontmostAppName: { "TestApp" }).snapshot().sourceApp == "TestApp")
        }
    }

    @Test func emptyPasteboardSnapshotIsEmpty() {
        withPasteboard { pb in
            pb.clearContents()
            #expect(SystemPasteboard(pasteboard: pb).snapshot().representations.isEmpty)
        }
    }
}
