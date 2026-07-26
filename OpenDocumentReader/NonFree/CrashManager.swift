import Foundation
import os

/// Crash reporting used to go to Crashlytics. OpenDocument.droid dropped its
/// Firebase dependency, so this mirrors the shell its `nonfree` package keeps:
/// errors are logged locally instead of being uploaded.
final class CrashManager {
    static let shared = CrashManager()

    private let logger = Logger(subsystem: "app.opendocument.reader", category: "crash")
    private var enabled = false
    private var customValues: [String: String] = [:]

    private init() {}

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    /// Context attached to everything reported afterwards, the way custom keys
    /// used to be attached to a Crashlytics report.
    func setCustomValue(_ value: String, forKey key: String) {
        customValues[key] = value
    }

    func log(_ message: String) {
        guard enabled else { return }

        logger.debug("\(message, privacy: .private)")
    }

    func log(_ error: Error) {
        // unconditionally, so a debug session shows the failure even with
        // reporting turned off
        logger.error("\(String(describing: error), privacy: .public) \(self.describedContext(), privacy: .private)")
    }

    private func describedContext() -> String {
        guard !customValues.isEmpty else { return "" }

        return customValues
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}
