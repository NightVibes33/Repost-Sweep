import SwiftUI

@main
struct RepostSweepApp: App {
    @StateObject private var session: TikTokWebSession
    @StateObject private var purchases: PurchaseManager
    @StateObject private var freeTier: FreeTierStore

    init() {
        _session = StateObject(wrappedValue: TikTokWebSession())
        _purchases = StateObject(wrappedValue: PurchaseManager())
        _freeTier = StateObject(wrappedValue: FreeTierStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(purchases)
                .environmentObject(freeTier)
        }
    }
}
