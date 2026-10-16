import Combine
import StoreKit
import UIKit

@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isSubscribed = false
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published var purchaseError: String?

    private var updates: Task<Void, Never>?

    func start() async {
        if updates == nil {
            updates = Task { [weak self] in
                await self?.listenForTransactions()
            }
        }
        await reloadProducts()
        await refreshEntitlements()
    }

    func product(id: String) -> Product? {
        products.first { $0.id == id }
    }

    func priceLine(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod.described else {
            return product.displayPrice
        }
        return "\(product.displayPrice) / \(period)"
    }

    var yearlySavingsPercent: Int? {
        guard
            let weekly = product(id: Monetization.weeklyProductID),
            let yearly = product(id: Monetization.yearlyProductID),
            weekly.subscription?.subscriptionPeriod.unit == .week,
            yearly.subscription?.subscriptionPeriod.unit == .year
        else {
            return nil
        }
        let yearAtWeeklyRate = weekly.price * Decimal(52)
        guard yearAtWeeklyRate > yearly.price, yearAtWeeklyRate > 0 else {
            return nil
        }
        let ratio = (yearAtWeeklyRate - yearly.price) / yearAtWeeklyRate
        let percent = NSDecimalNumber(decimal: ratio * Decimal(100)).doubleValue
        let rounded = Int(percent.rounded())
        return rounded > 0 ? rounded : nil
    }

    func reloadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: Monetization.allProductIDs)
            products = Monetization.allProductIDs.compactMap { id in
                loaded.first { $0.id == id }
            }
            if products.isEmpty == false {
                purchaseError = nil
            }
        } catch {
            purchaseError = "Subscriptions couldn’t be loaded. Free removals still work on this device."
        }
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.verified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "The purchase is pending approval. It will unlock when Apple finishes it."
            @unknown default:
                break
            }
        } catch {
            purchaseError = "The purchase didn’t complete. Try again, or use Restore purchases."
        }
    }

    func restore() async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if isSubscribed == false {
                purchaseError = "No active Repost Sweep subscription was found for this Apple ID."
            }
        } catch {
            purchaseError = "Restore didn’t finish. Check the Apple ID and try again."
        }
    }

    func manageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            purchaseError = "Subscription management isn’t available from this screen."
            return
        }
        do {
            try await AppStore.showManageSubscriptions(in: scene)
            await refreshEntitlements()
        } catch {
            purchaseError = "Apple’s subscription screen didn’t open."
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard let transaction = try? Self.verified(result) else { continue }
            await transaction.finish()
            await refreshEntitlements()
        }
    }

    private func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.verified(result) else { continue }
            guard transaction.revocationDate == nil else { continue }
            if Monetization.allProductIDs.contains(transaction.productID) {
                active = true
            }
        }
        isSubscribed = active
    }

    private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PurchaseFailure.unverified
        case .verified(let value):
            return value
        }
    }
}

private enum PurchaseFailure: Error {
    case unverified
}

extension Product.SubscriptionPeriod {
    var described: String {
        switch unit {
        case .day:
            return value == 1 ? "day" : "\(value) days"
        case .week:
            return value == 1 ? "week" : "\(value) weeks"
        case .month:
            return value == 1 ? "month" : "\(value) months"
        case .year:
            return value == 1 ? "year" : "\(value) years"
        @unknown default:
            return "period"
        }
    }
}
