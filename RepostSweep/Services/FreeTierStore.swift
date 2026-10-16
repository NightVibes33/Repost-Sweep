import Combine
import Foundation

/// Counts successful removals on this device. Reinstalling the app resets it.
/// A subscription bypasses the cap; StoreKit is the source of truth for that.
@MainActor
final class FreeTierStore: ObservableObject {
    @Published private(set) var used: Int

    private let defaultsKey = "freeRemovalsUsed"

    init() {
        let stored = UserDefaults.standard.integer(forKey: defaultsKey)
        used = max(0, stored)
    }

    var remaining: Int {
        max(0, Monetization.freeRemovalLimit - used)
    }

    func recordRemoval() {
        used += 1
        UserDefaults.standard.set(used, forKey: defaultsKey)
    }
}
