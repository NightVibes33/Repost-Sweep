import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0

    private let pages: [(symbol: String, title: String, body: String)] = [
        (
            "arrow.triangle.2.circlepath",
            "Sweep the\nrepost tab.",
            "See what you reposted and take it off your tab in one pass."
        ),
        (
            "checkmark.circle.fill",
            "You choose\nwhat goes.",
            "Original videos stay up. A removal only drops a video from your reposts."
        ),
        (
            "infinity",
            "Ten free.\nThen unlimited.",
            "A weekly or yearly plan removes the cap. This app is not affiliated with TikTok."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                MarkView(size: 28)
                Text("Repost Sweep")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Theme.pink : Theme.raised)
                        .frame(width: index == page ? 22 : 8, height: 8)
                }
            }
            .padding(.bottom, 18)
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                PrimaryButton(title: page == pages.count - 1 ? "Get started" : "Continue") {
                    if page == pages.count - 1 {
                        onFinish()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
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
            .padding(.bottom, 18)
        }
        .background {
            ZStack {
                Theme.canvas
                Circle()
                    .fill(Theme.pink.opacity(0.42))
                    .frame(width: 260, height: 260)
                    .blur(radius: 90)
                    .offset(x: 130, y: -220)
                Circle()
                    .fill(Theme.cyan.opacity(0.28))
                    .frame(width: 200, height: 200)
                    .blur(radius: 80)
                    .offset(x: -150, y: 20)
            }
            .ignoresSafeArea()
        }
        .readableColumn()
    }

    private func pageView(_ page: (symbol: String, title: String, body: String)) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 8)
            ZStack {
                Circle()
                    .fill(Theme.brand)
                    .frame(width: 132, height: 132)
                Circle()
                    .fill(Color.black)
                    .frame(width: 118, height: 118)
                Image(systemName: page.symbol)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(Theme.brand)
            }
            .accessibilityHidden(true)
            Text(page.title)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            Text(page.body)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}
