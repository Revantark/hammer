import Foundation

public enum DataDirectory {
    public static let environmentKey = "HAMMER_DATA_DIR"

    /// `HAMMER_DATA_DIR` if set, otherwise `~/Library/Application Support/Hammer`. Creates the directory.
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> URL {
        let url: URL
        if let override = environment[environmentKey], !override.isEmpty {
            url = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            url = support.appendingPathComponent("Hammer", isDirectory: true)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }
}
