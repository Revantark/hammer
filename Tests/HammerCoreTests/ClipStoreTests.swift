import Foundation
import Testing
@testable import HammerCore

@Suite struct ClipStoreTests {
    @Test func historyRoundTrip() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let store = ClipStore(directory: dir)
        var h = ClipHistory(); _ = h.insert(textEntry("a")); _ = h.insert(imageEntry())
        try store.saveHistory(h)
        #expect(ClipStore(directory: dir).loadHistory() == h)
    }

    @Test func missingIndexIsEmpty() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        #expect(ClipStore(directory: dir).loadHistory() == ClipHistory())
    }

    @Test func corruptIndexIsEmptyAndQuarantined() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let store = ClipStore(directory: dir)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("clipboard"), withIntermediateDirectories: true)
        try Data("{nope".utf8).write(to: dir.appendingPathComponent("clipboard/index.json"))
        #expect(store.loadHistory() == ClipHistory())
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("clipboard/index.corrupt.json").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("clipboard/index.json").path))
    }

    @Test func payloadRoundTrip() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let store = ClipStore(directory: dir)
        let id = UUID()
        let reps = [rep(PasteboardType.plainText, "hi"), rep(PasteboardType.rtf, "{\\rtf1 hi}"),
                    Representation(type: PasteboardType.png, data: Data(repeating: 7, count: 1_000_000))]
        try store.writePayload(reps, id: id)
        #expect(try store.readPayload(id: id) == reps)
    }

    @Test func deletePayloadsRemovesFiles() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let store = ClipStore(directory: dir)
        let id = UUID()
        try store.writePayload([rep(PasteboardType.plainText, "x")], id: id)
        store.deletePayloads([id])
        #expect(throws: (any Error).self) { try store.readPayload(id: id) }
    }

    @Test func pruneOrphansKeepsReferenced() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let store = ClipStore(directory: dir)
        let keep = UUID(), orphan = UUID()
        try store.writePayload([rep(PasteboardType.plainText, "k")], id: keep)
        try store.writePayload([rep(PasteboardType.plainText, "o")], id: orphan)
        store.pruneOrphans(keeping: [keep])
        #expect(try store.readPayload(id: keep).count == 1)
        #expect(throws: (any Error).self) { try store.readPayload(id: orphan) }
    }

    @Test func thumbnailRoundTrip() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let store = ClipStore(directory: dir); let id = UUID()
        try store.writeThumbnail(Data([1, 2, 3]), id: id)
        #expect(store.readThumbnail(id: id) == Data([1, 2, 3]))
        #expect(store.readThumbnail(id: UUID()) == nil)
    }

    @Test func deletePayloadsRemovesThumbnails() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let store = ClipStore(directory: dir); let id = UUID()
        try store.writePayload([rep(PasteboardType.plainText, "x")], id: id)
        try store.writeThumbnail(Data([1]), id: id)
        store.deletePayloads([id])
        #expect(store.readThumbnail(id: id) == nil)
    }

    @Test func pruneOrphansRemovesOrphanThumbnailsKeepsReferenced() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let store = ClipStore(directory: dir); let keep = UUID(), orphan = UUID()
        try store.writeThumbnail(Data([1]), id: keep)
        try store.writeThumbnail(Data([2]), id: orphan)
        store.pruneOrphans(keeping: [keep])
        #expect(store.readThumbnail(id: keep) == Data([1]))
        #expect(store.readThumbnail(id: orphan) == nil)
    }

    @Test func readMissingPayloadThrows() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        #expect(throws: (any Error).self) { try ClipStore(directory: dir).readPayload(id: UUID()) }
    }
}

@Suite struct ImageThumbnailerTests {
    @Test func thumbnailFitsMaxSize() throws {
        let t = try #require(ImageThumbnailer.thumbnail(data: makePNG(width: 2560, height: 1600), maxPixelSize: 600))
        #expect(t.width == 600 && t.height == 375)
    }

    @Test func thumbnailOfGarbageIsNil() {
        #expect(ImageThumbnailer.thumbnail(data: Data("not an image".utf8), maxPixelSize: 600) == nil)
    }

    @Test func smallImageNotUpscaled() throws {
        let t = try #require(ImageThumbnailer.thumbnail(data: makePNG(width: 40, height: 20), maxPixelSize: 600))
        #expect(t.width == 40 && t.height == 20)
    }
}
