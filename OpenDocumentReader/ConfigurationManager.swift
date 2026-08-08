import Foundation

struct ConfigurationManager {
    static let manager = ConfigurationManager()

    let configuration: AppType

    private init() {
        let productId = Bundle.main.bundleIdentifier?.lowercased() ?? ""

        configuration = AppType(rawValue: productId) ?? .lite
    }
}
