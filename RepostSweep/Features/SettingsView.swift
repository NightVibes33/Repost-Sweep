import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: TikTokWebSession
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var confirmSignOut = false
    @State private var showPrivacy = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("TikTok")
                                .font(Typeface.headline())
                                .foregroundStyle(Theme.ink)
                            if let account = session.account, account.uniqueId.isEmpty == false {
                                HStack(spacing: 12) {
                                    AvatarView(
                                        urlString: account.avatarURL,
                                        fallback: account.nickname.isEmpty ? account.uniqueId : account.nickname
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(account.nickname.isEmpty ? "@\(account.uniqueId)" : account.nickname)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Theme.ink)
                                        Text("@\(account.uniqueId)")
                                            .font(.subheadline)
                                            .foregroundStyle(Theme.muted)
                                    }
                                }
                            } else if session.hasSessionCookie {
                                Text("Signed in. Profile still loading.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.muted)
                            } else {
                                Text("Not signed in")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.muted)
                            }
                            Text(LegalCopy.session)
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            if session.hasSessionCookie == false && session.account == nil {
                                PrimaryButton(title: "Log in to TikTok", systemImage: "person.fill") {
                                    dismiss()
                                    session.beginLogin()
                                }
                            } else {
                                Button("Log out") {
                                    confirmSignOut = true
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.pink)
                            }
                        }
                    }

                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Subscription")
                                .font(Typeface.headline())
                                .foregroundStyle(Theme.ink)
                            Text(purchases.isSubscribed ? "Premium is active on this Apple ID." : "Free tier, unless a subscription is active.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                            if purchases.isSubscribed == false {
                                QuietButton(title: "See plans") {
                                    showPaywall = true
                                }
                            }
                            QuietButton(title: "Restore purchases") {
                                Task { await purchases.restore() }
                            }
                            QuietButton(title: "Manage subscription") {
                                Task { await purchases.manageSubscriptions() }
                            }
                            if let purchaseError = purchases.purchaseError {
                                Text(purchaseError)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.pink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    QuietButton(title: "Privacy") {
                        showPrivacy = true
                    }

                    Text(LegalCopy.notAffiliated)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(versionLine)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                .padding(20)
                .readableColumn()
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(isPresented: $showPrivacy) {
                PrivacyView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .sweepSheetChrome()
            }
            .confirmationDialog(
                "Log out of TikTok in this app?",
                isPresented: $confirmSignOut,
                titleVisibility: .visible
            ) {
                Button("Log out", role: .destructive) {
                    Task { await session.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears the in-app browser, including the TikTok session. Your password was never stored.")
            }
        }
    }

    private var versionLine: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Repost Sweep \(version) (\(build))"
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(LegalCopy.privacySections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(Typeface.headline())
                            .foregroundStyle(Theme.ink)
                        Text(section.body)
                            .font(Typeface.body())
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
            .readableColumn()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
