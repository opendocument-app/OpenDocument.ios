import Foundation

struct ConfigurationManager {
    static let manager = ConfigurationManager()
    
    private(set) var configuration: AppType!
    
    private init () {
        
        if let productId = Bundle.main.bundleIdentifier {
            configuration = AppType(rawValue: productId.lowercased()) ?? .lite
        }
    }
}
