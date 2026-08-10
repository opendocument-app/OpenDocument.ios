import Foundation
import os

/// Crash reporting used to go to Crashlytics. OpenDocument.droid dropped its
/// Firebase dependency, so this mirrors the shell its `nonfree` package keeps:
/// errors are logged locally instead of being uploaded, so nothing switches it
/// off.
final class CrashManager {
    static let shared = CrashManager()

    private let logger = Logger(subsystem: "app.opendocument.reader", category: "crash")
    private var customValues: [String: String] = [:]

    private init() {}

    /// Context attached to everything reported afterwards.
    func setCustomValue(_ value: String, forKey key: String) {
        customValues[key] = value
    }

    func log(_ message: String) {
        logger.debug("\(message, privacy: .private)")
    }

    func log(_ error: Error) {
        logger.error("\(String(describing: error), privacy: .public) \(self.describedContext(), privacy: .private)")
    }

    private func describedContext() -> String {
        guard !customValues.isEmpty else { return "" }

        return
            customValues
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}
