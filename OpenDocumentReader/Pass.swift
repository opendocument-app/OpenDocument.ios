import StoreKit
import UIKit

/// The yearly pass that Lite sells: no ads and all Pro features, for as long as the App Store
/// reports the subscription. Pro sells nothing, so there the pass is never active.
final class Pass {

    static let shared = Pass()

    /// The subscription Lite sells, the same id as on Android. It renews every year.
    static let productID = "pro_pass"

    /// Posted on the main thread when the pass becomes active. `userInfo["purchased"]` is true
    /// after a purchase from the sheet, and false when the App Store gives back an earlier one.
    static let didUnlock = Notification.Name("PassDidUnlock")

    /// What the App Store last said, kept so that a launch without the network keeps the pass.
    private static let activeKey = "passActive"

    /// Read from any thread: `Features.advancedEditing` asks while a document translates.
    var isActive: Bool {
        Features.withAds && UserDefaults.standard.bool(forKey: Pass.activeKey)
    }

    /// Whether "Support the app" is offered: in Lite, until the pass is active.
    var offersSupport: Bool {
        Features.withAds && !isActive
    }

    /// The product, once the App Store gives it. It carries the price.
    private(set) var product: Product?

    private var updates: Task<Void, Never>?

    private init() {}

    /// Asks the App Store at each launch, because a pass ends. Lite only.
    func start() {
        guard Features.withAds, updates == nil else { return }

        // a purchase on another device, a renewal, or a refund
        updates = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }

                await transaction.finish()
                await self?.refresh(purchased: false)
            }
        }

        Task {
            await refresh(purchased: false)
            _ = await loadProduct()
        }
    }

    /// The product with its price, asked again if the App Store did not give it before.
    @MainActor
    func loadProduct() async -> Product? {
        if let product { return product }

        do {
            product = try await Product.products(for: [Pass.productID]).first
        } catch {
            CrashManager.shared.log(error)
        }

        return product
    }

    enum PurchaseOutcome {
        case unlocked
        /// The user cancelled, or the purchase waits for approval, for example by a parent.
        case notNow
        /// No product: the App Store is not reachable, or the user is not signed in.
        case unavailable
    }

    @MainActor
    func purchase() async -> PurchaseOutcome {
        guard let product = await loadProduct() else { return .unavailable }

        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refresh(purchased: true)

                return isActive ? .unlocked : .notNow
            case .success(.unverified(_, let error)):
                CrashManager.shared.log(error)

                return .notNow
            case .userCancelled, .pending:
                return .notNow
            @unknown default:
                return .notNow
            }
        } catch {
            CrashManager.shared.log(error)

            return .unavailable
        }
    }

    /// Syncs with the App Store, for a user who bought the pass on another device or before a
    /// reinstall. Returns whether the pass is active afterwards.
    @MainActor
    func restore() async -> Bool {
        do {
            try await AppStore.sync()
        } catch {
            // the user cancelled the sign-in, or there is no network
            CrashManager.shared.log(error)
        }

        await refresh(purchased: false)

        return isActive
    }

    /// Reads the current entitlements, and tells the app if the pass just became active. An
    /// ended pass only turns the flag off: the ads come back with the next document.
    @MainActor
    private func refresh(purchased: Bool) async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            if transaction.productID == Pass.productID, transaction.revocationDate == nil {
                active = true
            }
        }

        let wasActive = isActive
        UserDefaults.standard.set(active, forKey: Pass.activeKey)

        if active, !wasActive {
            NotificationCenter.default.post(name: Pass.didUnlock, object: self, userInfo: ["purchased": purchased])
        }
    }
}
