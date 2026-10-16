import SwiftUI

@main
struct RepostSweepApp: App {
    @StateObject private var session: TikTokWebSession
    @StateObject private var purchases: PurchaseManager
    @StateObject private var freeTier: FreeTierStore
    @StateObject private var history: HistoryStore
    @StateObject private var runner: RemovalRunner

    init() {
        _session = StateObject(wrappedValue: TikTokWebSession())
        _purchases = StateObject(wrappedValue: PurchaseManager())
        _freeTier = StateObject(wrappedValue: FreeTierStore())
        _history = StateObject(wrappedValue: HistoryStore())
        _runner = StateObject(wrappedValue: RemovalRunner())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(purchases)
                .environmentObject(freeTier)
                .environmentObject(history)
                .environmentObject(runner)
        }
    }
}
