import Foundation
import Testing
@testable import HammerCore

@Suite struct FrecencyTests {
    let now = ManualClock().now()

    @Test func unknownIDScoresZero() {
        #expect(Frecency().score(id: "x", now: now) == 0)
    }

    @Test func moreUsesScoreHigher() {
        var f = Frecency()
        for _ in 0..<3 { f.recordUse(id: "a", at: now) }
        f.recordUse(id: "b", at: now)
        #expect(f.score(id: "a", now: now) > f.score(id: "b", now: now))
    }

    @Test func recencyBeatsOldEqualCount() {
        var f = Frecency()
        f.recordUse(id: "old", at: now.addingTimeInterval(-30 * day))
        f.recordUse(id: "old", at: now.addingTimeInterval(-30 * day))
        f.recordUse(id: "new", at: now)
        f.recordUse(id: "new", at: now)
        #expect(f.score(id: "new", now: now) > f.score(id: "old", now: now))
    }

    @Test func halfLifeIsSevenDays() {
        var f = Frecency()
        f.recordUse(id: "a", at: now)
        #expect(abs(f.score(id: "a", now: now.addingTimeInterval(7 * day)) - 0.5) < 1e-9)
    }

    @Test func recordUseUpdatesCountAndLastUsed() {
        var f = Frecency()
        f.recordUse(id: "a", at: now)
        f.recordUse(id: "a", at: now.addingTimeInterval(10))
        #expect(f.records["a"] == UsageRecord(count: 2, lastUsed: now.addingTimeInterval(10)))
    }

    @Test func storeRoundTrip() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let store = FrecencyStore(fileURL: dir.appendingPathComponent("frecency.json"))
        var f = Frecency()
        f.recordUse(id: "/Applications/Safari.app", at: now)
        try store.save(f)
        #expect(store.load() == f)
    }

    @Test func storeMissingFileGivesEmpty() {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        #expect(FrecencyStore(fileURL: dir.appendingPathComponent("nope.json")).load() == Frecency())
    }

    @Test func storeCorruptFileGivesEmpty() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let url = dir.appendingPathComponent("frecency.json")
        try Data("{garbage".utf8).write(to: url)
        #expect(FrecencyStore(fileURL: url).load() == Frecency())
    }
}

@Suite struct DataDirectoryTests {
    final class RecordingFileManager: FileManager, @unchecked Sendable {
        var created: [URL] = []
        override func createDirectory(at url: URL, withIntermediateDirectories: Bool, attributes: [FileAttributeKey: Any]? = nil) throws {
            created.append(url)
        }
    }

    @Test func dataDirUsesEnvOverride() throws {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let target = dir.appendingPathComponent("x")
        let resolved = try DataDirectory.resolve(environment: ["HAMMER_DATA_DIR": target.path])
        #expect(resolved.standardizedFileURL == target.standardizedFileURL)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir) && isDir.boolValue)
    }

    @Test func dataDirDefault() throws {
        let fm = RecordingFileManager()
        let resolved = try DataDirectory.resolve(environment: [:], fileManager: fm)
        #expect(resolved.path.hasSuffix("Library/Application Support/Hammer"))
        #expect(fm.created == [resolved])
    }
}
