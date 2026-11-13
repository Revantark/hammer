import Foundation
import HammerCore
import HammerMac

/// Measures per-keystroke search time against the real installed apps and a full clipboard history.
/// Exits 1 if any query's p99 is ≥ 16 ms.
@MainActor func runBench() -> Int32 {
    let budgetMs = 16.0
    let iterations = 200
    let catalog = AppCatalog(scanner: FileSystemAppScanner())
    let search = LauncherSearch(sources: [AppsSource(catalog: catalog)])
    var frecency = Frecency()
    for app in catalog.apps.prefix(20) { frecency.recordUse(id: app.path, at: Date()) }

    var history = ClipHistory()
    for i in 0..<ClipHistory.capacity {
        let text = String(repeating: "lorem ipsum \(i) ", count: 200)
        _ = history.insert(ClipClassifier.classify(PasteboardSnapshot(representations: [Representation(type: PasteboardType.plainText, data: Data(text.utf8))], sourceApp: "Bench"),
                                                   id: UUID(), at: Date())!.entry)
    }

    func measure(_ body: () -> Void) -> (p99: Double, max: Double) {
        var samples: [Double] = []
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        samples.sort()
        return (samples[Int(Double(samples.count - 1) * 0.99)], samples.last!)
    }

    print("apps indexed: \(catalog.apps.count)")
    var failed = false
    let top = search.search("saf", frecency: Frecency(), now: Date()).first?.title
    print("'saf' → \(top ?? "nothing")")
    if top != "Safari" { print("FAIL: Safari not found for 'saf'"); failed = true }
    let queries = (UInt8(ascii: "a")...UInt8(ascii: "z")).map { String(UnicodeScalar($0)) } + ["sa", "saf", "vsc", "term", "sys set", "xyzq"]
    for q in queries {
        let r = measure { _ = search.search(q, frecency: frecency, now: Date()) }
        if r.p99 >= budgetMs { failed = true }
        print(String(format: "launcher %-8@ p99 %.3f ms  max %.3f ms", "'\(q)'" as NSString, r.p99, r.max))
    }
    for q in ["lorem", "24", "zzz"] {
        let r = measure { _ = history.search(q) }
        if r.p99 >= budgetMs { failed = true }
        print(String(format: "clipboard %-7@ p99 %.3f ms  max %.3f ms", "'\(q)'" as NSString, r.p99, r.max))
    }
    print(failed ? "FAIL: p99 over \(budgetMs) ms" : "PASS: all p99 under \(budgetMs) ms")
    return failed ? 1 : 0
}

if CommandLine.arguments.contains("clipnav") {
    Task { @MainActor in exit(await runClipNavBench()) }
    RunLoop.main.run()
} else {
    exit(MainActor.assumeIsolated { runBench() })
}
