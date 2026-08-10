import UIKit

/// The ad banner, in a build that links no ad sdk. Nothing calls it; the shape is here so the
/// shared code compiles.
final class AdSlot {

    var onNoAd: (() -> Void)?
    var onAd: (() -> Void)?

    func start(in slot: UIView, from viewController: UIViewController) {}

    func resize() {}
}
