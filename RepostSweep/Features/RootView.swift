import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: TikTokWebSession
    @EnvironmentObject private var purchases: PurchaseManager
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            if session.showingDebugPage == false {
                WebViewHost(webView: session.webView)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            Group {
                if didFinishOnboarding {
                    HomeView()
                } else {
                    OnboardingView {
                        didFinishOnboarding = true
                        Task { await session.warmUp() }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.pink)
        .onOpenURL { url in
            session.handleAuthCallback(url)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                session.sceneBecameActive()
            }
        }
        .sheet(isPresented: $session.showingDebugPage) {
            DebugPageSheet()
                .sweepSheetChrome()
        }
        .task {
            await purchases.start()
            if didFinishOnboarding {
                await session.warmUp()
            }
        }
    }
}

struct DebugPageSheet: View {
    @EnvironmentObject private var session: TikTokWebSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebViewHost(webView: session.webView)
                .ignoresSafeArea(edges: .bottom)
                .background(Theme.canvas)
                .navigationTitle("TikTok page")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Close") {
                            session.showingDebugPage = false
                            dismiss()
                        }
                    }
                }
                .toolbarBackground(Theme.canvas, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
