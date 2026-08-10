import Foundation
import os

// Event and parameter names kept from the Firebase days so the reports stay
// comparable with OpenDocument.droid, which uses the same identifiers.
enum AnalyticsConstants {
    static let paramContentType = "content_type"
    static let paramContent = "content"
    static let paramItemName = "item_name"

    static let eventSelectContent = "select_content"
    static let eventViewItem = "view_item"
    static let eventSearch = "search"
}

/// Analytics used to go to Firebase. OpenDocument.droid dropped its Firebase
/// dependency, so this mirrors the shell its `nonfree` package keeps: the call
/// sites stay, but nothing leaves the device, so nothing switches it off.
final class AnalyticsManager {
    static let shared = AnalyticsManager()

    private let logger = Logger(subsystem: "app.opendocument.reader", category: "analytics")

    private init() {}

    func report(_ event: String, parameters: [String: Any]? = nil) {
        guard let parameters, !parameters.isEmpty else {
            logger.info("\(event, privacy: .public)")
            return
        }

        let described =
            parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        logger.info("\(event, privacy: .public) \(described, privacy: .private)")
    }

    func setCurrentScreen(_ name: String, className: String) {
        logger.info("screen \(name, privacy: .public) (\(className, privacy: .public))")
    }
}
