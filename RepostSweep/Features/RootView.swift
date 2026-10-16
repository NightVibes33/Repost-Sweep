import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: TikTokWebSession
    @EnvironmentObject private var purchases: PurchaseManager
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            WebViewHost(webView: session.webView)
                .opacity(session.showingLogin ? 1 : 0)
                .allowsHitTesting(session.showingLogin)
                .accessibilityHidden(!session.showingLogin)
                .ignoresSafeArea()

            if session.showingLogin {
                LoginChrome()
            } else if didFinishOnboarding {
                HomeView()
            } else {
                OnboardingView {
                    didFinishOnboarding = true
                    Task { await session.warmUp() }
                }
            }
        }
        .task {
            await purchases.start()
            if didFinishOnboarding && session.showingLogin == false {
                await session.warmUp()
            }
        }
    }
}

private struct LoginChrome: View {
    @EnvironmentObject private var session: TikTokWebSession

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sign in on TikTok")
                        .font(Typeface.headline())
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Button("Close") {
                        session.closeLogin()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                }
                Text(LegalCopy.password)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Reload") {
                        session.reloadLogin()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    if session.isPageLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                }
                if let pageError = session.pageError {
                    Text(pageError)
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)

            Spacer(minLength: 0)
                .allowsHitTesting(false)

            if let account = session.account, account.uniqueId.isEmpty == false {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Signed in as @\(account.uniqueId)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("The session stays in this browser. Continue when the page looks like your account.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(title: "Continue", systemImage: "arrow.right") {
                        session.closeLogin()
                    }
                }
                .padding(16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }
}
