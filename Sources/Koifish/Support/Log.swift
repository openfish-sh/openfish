import Foundation
import os

/// Thin wrapper over os.Logger so logs show up in Console.app / `log stream`
/// filtered by subsystem, without sprinkling `Logger(...)` everywhere.
enum Log {
    private static let logger = Logger(subsystem: "sh.koifish.Koifish", category: "app")

    static func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    static func debug(_ message: String) { logger.debug("\(message, privacy: .public)") }
    static func error(_ message: String) { logger.error("\(message, privacy: .public)") }
}

extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }
}
