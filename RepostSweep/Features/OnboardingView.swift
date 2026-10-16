import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0

    private let pages: [(title: String, body: String)] = [
        (
            "Sweep the\nrepost tab.",
            "See what you reposted and take it off your tab in one pass."
        ),
        (
            "You choose\nwhat goes.",
            "Original videos stay up. A removal only drops a video from your reposts."
        ),
        (
            "Ten free.\nThen unlimited.",
            "A weekly or yearly plan removes the cap. This app is not affiliated with TikTok."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                MarkView(size: 32)
                Text("Repost Sweep")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 16) {
                        Spacer(minLength: 12)
                        Text(pages[index].title)
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                            .minimumScaleFactor(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(pages[index].body)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
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
                    .fill(Theme.pink.opacity(0.45))
                    .frame(width: 220, height: 220)
                    .blur(radius: 90)
                    .offset(x: 120, y: -180)
                Circle()
                    .fill(Theme.cyan.opacity(0.28))
                    .frame(width: 180, height: 180)
                    .blur(radius: 80)
                    .offset(x: -140, y: -40)
            }
            .ignoresSafeArea()
        }
        .readableColumn()
    }
}
