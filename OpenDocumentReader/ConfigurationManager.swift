import Foundation

struct ConfigurationManager {
    static let manager = ConfigurationManager()
    
    private(set) var configuration: String!
    
    private init () {
        if let configuration = Bundle.main.infoDictionary?["Configurations"] as? String {
            self.configuration = configuration
        } 
    }
}
