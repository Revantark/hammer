import AppKit
import HammerCore
import HammerMac

/// Arrows through a realistic 25-entry clipboard in the real panel (offscreen window, real store and decoders)
/// and times each step on the main thread, including layout and drawing. Exits 1 if a step's p95 ≥ 16 ms.
@MainActor func runClipNavBench() async -> Int32 {
    _ = NSApplication.shared
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hammer-clipnav-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let pasteboard = BenchPasteboard()
    let clipboard = ClipboardController(pasteboard: pasteboard, store: ClipStore(directory: dir.appendingPathComponent("clip")), clock: SystemClock())
    let base = benchScreenshot()
    let code = (try? String(contentsOfFile: #filePath.replacingOccurrences(of: "HammerBench/ClipNavBench.swift", with: "HammerMac/UI/PanelViewController.swift"), encoding: .utf8)) ?? String(repeating: "let x = 1;\n", count: 2_000)
    let log = (0..<4_000).map { "2026-11-13 10:\($0 % 60):00 INFO request \($0) handled in \($0 % 97) ms path=/api/v1/items/\($0)" }.joined(separator: "\n")
    let samples: [(String, [Representation])] = (0..<25).map { i in
        switch i % 5 {
        case 0: return ("image", [Representation(type: PasteboardType.png, data: benchScreenshotPNG(base, variant: i))])
        case 1: return ("short", [Representation(type: PasteboardType.plainText, data: Data("https://example.com/item/\(i)".utf8))])
        case 2: return ("code", [Representation(type: PasteboardType.plainText, data: Data((code + "\n// \(i)").utf8))])
        case 3: return ("log", [Representation(type: PasteboardType.plainText, data: Data((log + "\n\(i)").utf8))])
        default: return ("prose", [Representation(type: PasteboardType.plainText, data: Data(String(repeating: "The quick brown fox \(i) jumps over the lazy dog. ", count: 60).utf8))])
        }
    }
    for (_, reps) in samples { pasteboard.write(reps); clipboard.poll() }
    precondition(clipboard.history.entries.count == samples.count, "expected \(samples.count) distinct entries")

    let model = PanelModel()
    let launcher = LauncherController(search: LauncherSearch(sources: []), store: FrecencyStore(fileURL: dir.appendingPathComponent("f.json")),
                                      launcher: BenchLauncher(), pasteboard: pasteboard, clock: SystemClock())
    let controller = PanelViewController(model: model, launcher: launcher, clipboard: clipboard, pasteSender: BenchPasteSender(),
                                         icons: IconProvider(), thumbnails: ClipThumbnails(clipboard: clipboard), clock: SystemClock(),
                                         settings: { Settings() })
    let window = NSWindow(contentRect: NSRect(x: -6_000, y: -6_000, width: 800, height: 480), styleMask: .borderless, backing: .buffered, defer: false)
    window.contentViewController = controller
    window.orderFrontRegardless()

    func ms(_ start: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 }
    func flush() { window.layoutIfNeeded(); window.displayIfNeeded() }

    model.hotkey(.clipboard)
    controller.preferredContentSize = controller.preferredPanelSize
    window.setContentSize(controller.preferredPanelSize)
    flush()
    await controller.previewTask?.value

    // Newest first: kinds in display order are the samples reversed.
    let order = samples.map(\.0).reversed().map { $0 }
    var step: [String: [Double]] = [:]
    var imageReady: [Double] = []
    for pass in 0..<4 {
        for i in 1..<order.count {
            let start = DispatchTime.now().uptimeNanoseconds
            controller.handleKey(.down)
            flush()
            let sync = ms(start)
            if pass > 0 { step[order[i], default: []].append(sync) }
            if let task = controller.previewTask {
                await task.value
                flush()
                if pass > 0 { imageReady.append(ms(start)) }
            }
        }
        for _ in 1..<order.count { controller.handleKey(.up) }
        flush()
        await controller.previewTask?.value
    }

    func stats(_ xs: [Double]) -> String {
        let s = xs.sorted()
        guard !s.isEmpty else { return "n=0" }
        return String(format: "n=%d  p50 %.2f ms  p95 %.2f ms  max %.2f ms", s.count, s[s.count / 2], s[Int(Double(s.count - 1) * 0.95)], s.last!)
    }
    var failed = false
    for kind in ["short", "prose", "code", "log", "image"] {
        let xs = step[kind] ?? []
        print("↓ onto \(kind.padding(toLength: 6, withPad: " ", startingAt: 0)) main thread: \(stats(xs))")
        if let p95 = xs.sorted().dropFirst(Int(Double(xs.count - 1) * 0.95)).first, p95 >= 16 { failed = true }
    }
    print(imageReady.isEmpty ? "↓ onto image: preview shown in the same step (saved preview)"
                             : "↓ onto image → preview shown (background decode): \(stats(imageReady))")
    print(failed ? "FAIL: a step's main-thread p95 is ≥ 16 ms (drops a frame)" : "PASS: every step under 16 ms")
    return failed ? 1 : 0
}

@MainActor final class BenchPasteboard: PasteboardAccess {
    var changeCount = 0
    private var reps: [Representation] = []
    func snapshot() -> PasteboardSnapshot { PasteboardSnapshot(representations: reps, sourceApp: "Bench") }
    @discardableResult func write(_ reps: [Representation]) -> Int { self.reps = reps; changeCount += 1; return changeCount }
}

@MainActor final class BenchPasteSender: PasteSending {
    var isTrusted: Bool { false }
    func sendPaste() {}
    func requestTrust() {}
}

@MainActor final class BenchLauncher: AppLaunching {
    func openApp(at path: String) {}
}

/// The system wallpaper check-memory.sh uses, as a stand-in for a screenshot.
func benchScreenshot() -> NSImage? {
    NSImage(contentsOfFile: "/System/Library/Desktop Pictures/.thumbnails/Calibrate 5120x3200.jpg")
}

/// A distinct 2560×1600 PNG per `variant` (identical copies would be deduplicated into one entry).
func benchScreenshotPNG(_ source: NSImage?, variant: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2560, pixelsHigh: 1600, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if let source { source.draw(in: NSRect(x: 0, y: 0, width: 2560, height: 1600)) } else { NSColor.systemTeal.setFill(); NSRect(x: 0, y: 0, width: 2560, height: 1600).fill() }
    NSColor(hue: CGFloat(variant) / 25, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
    NSRect(x: 100 + variant * 40, y: 100, width: 600, height: 400).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
