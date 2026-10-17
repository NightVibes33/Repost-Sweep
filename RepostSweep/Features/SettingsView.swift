import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: TikTokWebSession
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = true
    @State private var confirmSignOut = false
    @State private var showPaywall = false
    @State private var replayOnboarding = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let account = session.account, account.uniqueId.isEmpty == false {
                        HStack(spacing: 12) {
                            AvatarView(
                                urlString: account.avatarURL,
                                fallback: account.nickname.isEmpty ? account.uniqueId : account.nickname
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.nickname.isEmpty ? "@\(account.uniqueId)" : account.nickname)
                                    .font(Typeface.body)
                                    .foregroundStyle(Theme.ink)
                                Text("@\(account.uniqueId)")
                                    .font(Typeface.caption)
                                    .foregroundStyle(Theme.muted)
                                if let stats = account.statsLine {
                                    Text(stats)
                                        .font(Typeface.caption)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    } else if session.hasSessionCookie {
                        Text("Signed in. Profile still loading.")
                            .font(Typeface.body)
                            .foregroundStyle(Theme.muted)
                    } else {
                        Text("Not signed in")
                            .font(Typeface.body)
                            .foregroundStyle(Theme.muted)
                    }
                    Text(LegalCopy.session)
                        .font(Typeface.caption)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if session.hasSessionCookie == false && session.account == nil {
                        TikTokLoginControl(phase: session.appLoginPhase) {
                            dismiss()
                            session.beginLogin()
                        } onCancel: {
                            session.cancelLogin()
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    } else {
                        Button("Log out", role: .destructive) {
                            confirmSignOut = true
                        }
                    }
                } header: {
                    Text("Account")
                }
                .listRowBackground(Theme.card)

                Section {
                    Text(purchases.isSubscribed ? "Premium is active on this Apple ID." : "Free tier, unless a subscription is active.")
                        .font(Typeface.secondary)
                        .foregroundStyle(Theme.muted)
                    if purchases.isSubscribed == false {
                        Button("See plans") {
                            showPaywall = true
                        }
                    }
                    Button("Restore purchases") {
                        Task { await purchases.restore() }
                    }
                    Button("Manage subscription") {
                        Task { await purchases.manageSubscriptions() }
                    }
                    if let purchaseError = purchases.purchaseError {
                        Text(purchaseError)
                            .font(Typeface.caption)
                            .foregroundStyle(Theme.pink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Subscription")
                }
                .listRowBackground(Theme.card)

                Section {
                    Button("Show onboarding") {
                        replayOnboarding = true
                        dismiss()
                    }
                    NavigationLink("Privacy") {
                        PrivacyView()
                    }
                } header: {
                    Text("App")
                }
                .listRowBackground(Theme.card)

                Section {
                    Text(LegalCopy.notAffiliated)
                        .font(Typeface.caption)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(versionLine)
                        .font(Typeface.caption)
                        .foregroundStyle(Theme.muted)
                }
                .listRowBackground(Theme.card)
            }
            .listStyle(.insetGrouped)
            .listRowBackground(Theme.card)
            .listRowSeparatorTint(Theme.line)
            .scrollContentBackground(.hidden)
            .tint(Theme.ink)
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
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onDisappear {
                if replayOnboarding {
                    didFinishOnboarding = false
                }
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
            VStack(alignment: .leading, spacing: 24) {
                ForEach(LegalCopy.privacySections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(Typeface.title)
                            .foregroundStyle(Theme.ink)
                        Text(section.body)
                            .font(Typeface.body)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Theme.margin)
            .readableColumn()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
