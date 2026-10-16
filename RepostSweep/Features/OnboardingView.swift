import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0

    private let pages: [(symbol: String, title: String, body: String)] = [
        (
            "arrow.triangle.2.circlepath",
            "Clear the repost tab without tapping every video.",
            "Repost Sweep lists the videos you reposted, lets you choose which ones to drop, and removes them with a pause between each one."
        ),
        (
            "lock.shield",
            "You sign in on TikTok’s own page.",
            LegalCopy.password + " " + LegalCopy.session
        ),
        (
            "sparkles",
            "Ten free removals. Then a subscription.",
            "Try it on \(Monetization.freeRemovalLimit) reposts. A weekly or yearly plan removes the cap. Cancel anytime in App Store settings."
        ),
        (
            "hand.raised",
            "Independent of TikTok.",
            LegalCopy.notAffiliated + " If TikTok changes its website, the app says so and stops, instead of guessing."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("REPOST SWEEP")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .tracking(1.2)
                Spacer()
                Text("\(page + 1) of \(pages.count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    OnboardingPage(
                        symbol: pages[index].symbol,
                        title: pages[index].title,
                        message: pages[index].body
                    )
                    .tag(index)
                    .padding(.horizontal, 24)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Theme.accent : Theme.raised)
                        .frame(width: index == page ? 22 : 8, height: 8)
                }
            }
            .padding(.bottom, 20)
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                PrimaryButton(
                    title: page == pages.count - 1 ? "Get started" : "Continue",
                    systemImage: page == pages.count - 1 ? "checkmark" : "arrow.right"
                ) {
                    if page == pages.count - 1 {
                        onFinish()
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            page += 1
                        }
                    }
                }
                Text(LegalCopy.notAffiliated)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .readableColumn()
    }
}

private struct OnboardingPage: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ZStack {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 84, height: 84)
                Image(systemName: symbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.accentInk)
            }
            .padding(.top, 28)
            .accessibilityHidden(true)

            Text(title)
                .font(Typeface.display())
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(Typeface.body())
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
