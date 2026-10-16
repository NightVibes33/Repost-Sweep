import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var session: TikTokWebSession
    @EnvironmentObject private var purchases: PurchaseManager
    @EnvironmentObject private var freeTier: FreeTierStore

    @State private var showLibrary = false
    @State private var showSettings = false
    @State private var showPaywall = false
    @State private var showSiteChange = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("REPOST SWEEP")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .tracking(1.2)
                        Text("Clear the repost tab.")
                            .font(Typeface.display())
                            .foregroundStyle(Theme.ink)
                        Text("Choose the videos you shared onto your profile and remove those reposts in one pass. Original videos stay up.")
                            .font(Typeface.body())
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    accountCard
                    FreeMeter(
                        used: freeTier.used,
                        limit: Monetization.freeRemovalLimit,
                        subscribed: purchases.isSubscribed
                    )

                    if purchases.isSubscribed == false {
                        QuietButton(title: "See weekly and yearly plans") {
                            showPaywall = true
                        }
                    }

                    if let banner = session.banner {
                        Text(banner)
                            .font(.footnote)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.raised)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if session.siteChangeMessage != nil {
                        Button {
                            showSiteChange = true
                        } label: {
                            SurfaceCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("TikTok’s page changed")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Theme.ink)
                                    Text("The app stopped instead of guessing. Read what that means.")
                                        .font(.footnote)
                                        .foregroundStyle(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("How a sweep works")
                            .font(Typeface.headline())
                            .foregroundStyle(Theme.ink)
                        step("1", "Sign in on TikTok’s website, inside the app.")
                        step("2", "Review the list. Keep the reposts you still want.")
                        step("3", "Sweep removes the rest, with a few seconds between each one.")
                    }

                    Text(LegalCopy.notAffiliated)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(20)
                .readableColumn()
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Theme.ink)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(isPresented: $showLibrary) {
                LibraryView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showSiteChange) {
                SiteChangeView()
            }
        }
    }

    private var accountCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                if let account = session.account, account.uniqueId.isEmpty == false {
                    Text("@\(account.uniqueId)")
                        .font(Typeface.headline())
                        .foregroundStyle(Theme.ink)
                    if account.nickname.isEmpty == false {
                        Text(account.nickname)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                    PrimaryButton(
                        title: session.reposts.isEmpty ? "Find my reposts" : "Review reposts",
                        systemImage: "list.bullet",
                        enabled: session.isWorking == false
                    ) {
                        showLibrary = true
                        if session.reposts.isEmpty {
                            Task { await session.loadReposts() }
                        }
                    }
                    QuietButton(title: "Scan again") {
                        showLibrary = true
                        Task { await session.loadReposts() }
                    }
                } else {
                    Text("TikTok isn’t connected")
                        .font(Typeface.headline())
                        .foregroundStyle(Theme.ink)
                    Text("Sign in on TikTok’s page. Your password stays there.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(title: "Sign in to TikTok", systemImage: "person") {
                        session.beginLogin()
                    }
                }
                if session.isWorking {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(session.statusText.isEmpty ? "Working…" : session.statusText)
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accentInk)
                .frame(width: 28, height: 28)
                .background(Theme.accent)
                .clipShape(Circle())
            Text(text)
                .font(Typeface.body())
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
