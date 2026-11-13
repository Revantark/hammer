import Foundation
import Testing
@testable import HammerMac

@MainActor @Suite struct FSEventsWatcherTests {
    @Test func firesOnNewAppInWatchedDir() async {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let watcher = FSEventsWatcher(latency: 0.05)
        watcher.start(paths: [dir]) { continuation.yield() }
        defer { watcher.stop() }
        makeFakeApp("New", in: dir)
        #expect(await firstEvent(stream))
    }

    @Test func stopPreventsCallbacks() async {
        let dir = makeTempDir(); defer { removeTempDir(dir) }
        var stoppedCalls = 0
        let a = FSEventsWatcher(latency: 0.05)
        a.start(paths: [dir]) { stoppedCalls += 1 }
        a.stop()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let b = FSEventsWatcher(latency: 0.05)
        b.start(paths: [dir]) { continuation.yield() }
        defer { b.stop() }
        makeFakeApp("Late", in: dir)
        #expect(await firstEvent(stream))
        #expect(stoppedCalls == 0)
    }
}
