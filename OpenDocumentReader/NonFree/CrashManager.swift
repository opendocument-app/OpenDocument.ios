import Foundation
import os

/// Logs errors locally without uploading them.
final class CrashManager {
    static let shared = CrashManager()

    private let logger = Logger(subsystem: "app.opendocument.reader", category: "crash")
    private var customValues: [String: String] = [:]
    private let lock = NSLock()

    private init() {}

    /// Context attached to everything reported afterwards.
    func setCustomValue(_ value: String, forKey key: String) {
        lock.withLock { customValues[key] = value }
    }

    func log(_ message: String) {
        logger.debug("\(message, privacy: .private)")
    }

    func log(_ error: Error) {
        logger.error("\(String(describing: error), privacy: .public) \(self.describedContext(), privacy: .private)")
    }

    private func describedContext() -> String {
        lock.withLock {
            customValues
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
        }
    }
}
