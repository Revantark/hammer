import CoreServices
import Foundation
import HammerCore

/// Calls back on the main queue when anything changes under the watched paths.
@MainActor public final class FSEventsWatcher: DirectoryWatching {
    private let latency: TimeInterval
    private var stream: FSEventStreamRef?
    private var handler: (@MainActor () -> Void)?

    public init(latency: TimeInterval = 0.3) {
        self.latency = latency
    }

    public func start(paths: [URL], onChange: @escaping @MainActor () -> Void) {
        stop()
        handler = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.handler?() }
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths.map(\.path) as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        handler = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
