import Foundation

/// StoreKit product identifiers for Repost Sweep.
///
/// This is the only place those IDs are defined. Create auto-renewable
/// subscriptions in App Store Connect with these exact product IDs before
/// shipping a signed build. They are placeholders until then: a sideloaded
/// or unsigned build will not receive prices from the App Store.
///
/// Suggested starting prices (set in App Store Connect, not in this file):
/// weekly $4.99, yearly $29.99. The app displays whatever price StoreKit
/// returns for the signed build.
enum Monetization {
    /// Auto-renewable subscription, period P1W.
    static let weeklyProductID = "app.repostsweep.premium.weekly"

    /// Auto-renewable subscription, period P1Y.
    static let yearlyProductID = "app.repostsweep.premium.yearly"

    /// Subscription group name to create in App Store Connect.
    static let subscriptionGroupName = "Repost Sweep Premium"

    /// Removals that work without a subscription. Counted on this device only.
    static let freeRemovalLimit = 10

    static let allProductIDs = [weeklyProductID, yearlyProductID]
}
