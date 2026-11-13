import Foundation
import HammerCore

/// Test hooks for the memory/latency scripts. Only active when HAMMER_DEBUG_SIGNALS=1.
/// SIGUSR1 → launcher, SIGUSR2 → clipboard, SIGHUP → hide. With HAMMER_LOG_TIMING=1, prints `show_ms=<n>`.
/// SIGINFO → types HAMMER_DEBUG_CLIP_QUERY into the search (exercises the clipboard archive).
@MainActor final class DebugHooks {
    let isEnabled: Bool
    private let logTiming: Bool
    private var sources: [DispatchSourceSignal] = []
    private var requestedAt: UInt64?

    init(show: @escaping (HotkeyRole) -> Void, hide: @escaping () -> Void, search: @escaping (String) -> Void,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        isEnabled = environment["HAMMER_DEBUG_SIGNALS"] == "1"
        logTiming = environment["HAMMER_LOG_TIMING"] == "1"
        guard isEnabled else { return }
        let query = environment["HAMMER_DEBUG_CLIP_QUERY"] ?? ""
        let actions: [(Int32, () -> Void)] = [(SIGUSR1, { show(.launcher) }), (SIGUSR2, { show(.clipboard) }), (SIGHUP, hide),
                                              (SIGINFO, { search(query) })]
        for (signalNumber, action) in actions {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { action() } }
            source.resume()
            sources.append(source)
        }
        print("hammer_ready pid=\(ProcessInfo.processInfo.processIdentifier)")
        fflush(stdout)
    }

    func markShowRequested() {
        guard logTiming else { return }
        requestedAt = DispatchTime.now().uptimeNanoseconds
    }

    func markShown() {
        guard logTiming, let start = requestedAt else { return }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        print(String(format: "show_ms=%.2f", ms))
        fflush(stdout)
        requestedAt = nil
    }
}
