import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: TikTokWebSession
    @EnvironmentObject private var purchases: PurchaseManager
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            if session.showingLogin == false && session.showingDebugPage == false {
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
        .sheet(isPresented: $session.showingLogin, onDismiss: { session.loginSheetDismissed() }) {
            LoginSheet()
                .sweepSheetChrome()
        }
        .sheet(isPresented: $session.showingDebugPage) {
            DebugPageSheet()
                .sweepSheetChrome()
        }
        .task {
            await purchases.start()
            if didFinishOnboarding && session.showingLogin == false {
                await session.warmUp()
            }
        }
    }
}

struct LoginSheet: View {
    @EnvironmentObject private var session: TikTokWebSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                MarkView(size: 36)
                Spacer()
                Button {
                    session.closeLogin()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)
                        .background(Theme.raised)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Text("Log in to TikTok")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Text("TikTok’s own sign-in, inside this sheet. Repost Sweep never sees your password.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 6)

            progressBar
                .padding(.horizontal, 20)
                .padding(.top, 14)

            WebViewHost(webView: session.webView)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if let pageError = session.pageError {
                Text(pageError)
                    .font(.footnote)
                    .foregroundStyle(Theme.pink)
                    .padding(.horizontal, 20)
            }

            HStack {
                Button("Reload") {
                    session.reloadLogin()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.muted)
                Spacer()
                if session.isPageLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.pink)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised)
                Capsule()
                    .fill(Theme.brand)
                    .frame(width: max(8, proxy.size.width * session.loginProgress))
            }
        }
        .frame(height: 3)
        .accessibilityLabel("Loading TikTok")
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
