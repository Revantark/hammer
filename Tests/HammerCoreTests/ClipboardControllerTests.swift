import Foundation
import Testing
@testable import HammerCore

@MainActor @Suite struct ClipboardControllerTests {
    func make(_ dir: URL, _ pb: FakePasteboard, clock: ManualClock = ManualClock()) -> ClipboardController {
        ClipboardController(pasteboard: pb, store: ClipStore(directory: dir), clock: clock)
    }

    @Test func launchClipboardNotCaptured() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let pb = FakePasteboard(); pb.copy(textSnapshot("old"))
        let c = make(dir, pb)
        c.poll()
        #expect(c.history.entries.isEmpty)
    }

    @Test func newTextCaptured() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let pb = FakePasteboard(); let c = make(dir, pb)
        var changes = 0; c.onChange = { changes += 1 }
        pb.copy(textSnapshot("hello"))
        c.poll()
        #expect(c.history.entries.map(\.snippet) == ["hello"])
        #expect(blobCount(dir) == 1)
        #expect(changes == 1)
        #expect(c.payload(id: c.history.entries[0].id) == [rep(PasteboardType.plainText, "hello")])
    }

    @Test func imageCaptureWritesSmallListThumbnail() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let pb = FakePasteboard(); let c = make(dir, pb)
        pb.copy(PasteboardSnapshot(representations: [Representation(type: PasteboardType.png, data: makePNG(width: 2560, height: 1600))], sourceApp: nil))
        c.poll()
        let data = try #require(c.listThumbnailData(id: c.history.entries[0].id))
        let image = try #require(ImageThumbnailer.thumbnail(data: data, maxPixelSize: 1_000))
        #expect(max(image.width, image.height) == ClipboardController.listThumbnailPixels)
    }

    @Test func textCaptureHasNoThumbnail() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let pb = FakePasteboard(); let c = make(dir, pb)
        pb.copy(textSnapshot("hi")); c.poll()
        #expect(c.listThumbnailData(id: c.history.entries[0].id) == nil)
    }

    @Test func unchangedCountIgnored() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let pb = FakePasteboard(); let c = make(dir, pb)
        pb.copy(textSnapshot("a")); c.poll(); c.poll(); c.poll()
        #expect(c.history.entries.count == 1)
    }

    @Test func fileCopyIgnored() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let pb = FakePasteboard(); let c = make(dir, pb)
        var changes = 0; c.onChange = { changes += 1 }
        pb.copy(PasteboardSnapshot(representations: [rep(PasteboardType.fileURL, "file:///a")], sourceApp: "Finder"))
        c.poll()
        #expect(c.history.entries.isEmpty)
        #expect(changes == 0)
    }

    @Test func duplicateMovesToTopNoNewBlob() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let pb = FakePasteboard(); let c = make(dir, pb)
        pb.copy(textSnapshot("a")); c.poll()
        pb.copy(textSnapshot("b")); c.poll()
        pb.copy(textSnapshot("a")); c.poll()
        #expect(c.history.entries.map(\.snippet) == ["a", "b"])
        #expect(blobCount(dir) == 2)
    }

    @Test func evictionDeletesBlob() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let pb = FakePasteboard(); let c = make(dir, pb)
        for i in 0..<26 { pb.copy(textSnapshot("\(i)")); c.poll() }
        #expect(c.history.entries.count == 25)
        #expect(blobCount(dir) == 25)
    }

    @Test func historyPersistsAcrossInstances() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let pb = FakePasteboard(); let c = make(dir, pb)
        pb.copy(textSnapshot("keep")); c.poll()
        #expect(make(dir, pb).history.entries.map(\.snippet) == ["keep"])
    }

    @Test func orphanBlobsPrunedAtInit() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        try ClipStore(directory: dir).writePayload([rep(PasteboardType.plainText, "x")], id: UUID())
        _ = make(dir, FakePasteboard())
        #expect(blobCount(dir) == 0)
    }

    @Test func pasteWritesPayloadAndMovesToTop() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let pb = FakePasteboard(); let c = make(dir, pb)
        for t in ["a", "b", "c"] { pb.copy(textSnapshot(t)); c.poll() }
        let target = c.history.entries[2]  // "a"
        let log = EventLog(); let sender = FakePasteSender(log: log)
        let outcome = c.paste(id: target.id, sender: sender, beforePaste: { log.events.append("hide") })
        #expect(outcome == .pasted)
        #expect(pb.written.last == [rep(PasteboardType.plainText, "a")])
        #expect(c.history.entries[0].id == target.id)
        #expect(log.events == ["hide", "paste"])
    }

    @Test func ownWriteNotRecapturedAsNew() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let pb = FakePasteboard(); let c = make(dir, pb)
        pb.copy(textSnapshot("a")); c.poll(); pb.copy(textSnapshot("b")); c.poll()
        _ = c.paste(id: c.history.entries[1].id, sender: FakePasteSender(), beforePaste: {})
        var changes = 0; c.onChange = { changes += 1 }
        c.poll()
        #expect(c.history.entries.map(\.snippet) == ["a", "b"])
        #expect(changes == 0)
    }

    @Test func pasteWithoutTrustCopiesOnly() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let pb = FakePasteboard(); let c = make(dir, pb)
        pb.copy(textSnapshot("a")); c.poll()
        let log = EventLog(); let sender = FakePasteSender(log: log); sender.isTrusted = false
        #expect(c.paste(id: c.history.entries[0].id, sender: sender, beforePaste: {}) == .copiedOnly)
        #expect(log.events == ["requestTrust"])
        #expect(pb.written.count == 1)
    }

    @Test func pasteUnknownIDReturnsNil() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let c = make(dir, FakePasteboard())
        #expect(c.paste(id: UUID(), sender: FakePasteSender(), beforePaste: {}) == nil)
    }

    @Test func clearAllRemovesEverything() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let pb = FakePasteboard(); let c = make(dir, pb)
        pb.copy(textSnapshot("a")); c.poll(); pb.copy(textSnapshot("b")); c.poll()
        var changes = 0; c.onChange = { changes += 1 }
        c.clearAll()
        #expect(c.history.entries.isEmpty)
        #expect(blobCount(dir) == 0)
        #expect(ClipStore(directory: dir).loadHistory().entries.isEmpty)
        #expect(changes == 1)
    }

    @Test func saveFailureKeepsInMemory() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let pb = FakePasteboard(); let c = make(dir, pb)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        pb.copy(textSnapshot("a")); c.poll()
        #expect(c.history.entries.map(\.snippet) == ["a"])
    }
}
