import UIKit

/// Ad privacy choices, in a build that never asked for consent. Nothing calls these; the shape is
/// here so the shared code compiles.
enum AdPrivacy {

    static func refresh(completion: @escaping () -> Void) {
        completion()
    }

    static var optionsAvailable: Bool { false }

    static func presentOptions(from viewController: UIViewController, completion: @escaping () -> Void) {
        completion()
    }
}
