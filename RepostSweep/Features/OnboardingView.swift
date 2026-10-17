import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                MarkView(size: 32)
                Text("Repost Sweep")
                    .font(Typeface.secondary)
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 8)

            TabView(selection: $page) {
                ringPage.tag(0)
                focusPage.tag(1)
                proofPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            PageDots(count: 3, index: page)
                .padding(.bottom, 16)

            VStack(spacing: 12) {
                PrimaryButton(title: page == 2 ? "Get started" : "Continue") {
                    if page == 2 {
                        onFinish()
                    } else {
                        withAnimation(Motion.spring) {
                            page += 1
                        }
                    }
                }
                Text(LegalCopy.notAffiliated)
                    .font(Typeface.caption)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 16)
        }
        .background(ScreenBackdrop())
        .readableColumn()
    }

    private var ringPage: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 8)
            Text("Clear the\nrepost tab.")
                .font(Typeface.onboarding)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            MetricRing(progress: 0.72) {
                VStack(spacing: 2) {
                    Text("10")
                        .font(Typeface.hero)
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                    Text("free")
                        .font(Typeface.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(width: ScreenLayout.onboardingRing, height: ScreenLayout.onboardingRing)
            Text("See every repost, then take the ones you choose off your tab.")
                .font(Typeface.body)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, Theme.margin)
    }

    private var focusPage: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 12)
            Text("You pick\nwhat leaves.")
                .font(Typeface.onboarding)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            AppGlyph(size: ScreenLayout.isNarrow ? 128 : 168)
                .padding(.vertical, 12)
            Text("Original videos stay up. A removal only drops a video from your reposts.")
                .font(Typeface.body)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer(minLength: 24)
        }
        .padding(.horizontal, Theme.margin)
    }

    private var proofPage: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 8)
            Text("Ten free.\nThen unlimited.")
                .font(Typeface.onboarding)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            VStack(spacing: 20) {
                LaurelLine(title: "Originals stay up", detail: "Creators keep their videos")
                LaurelLine(title: "Chosen by you", detail: "Nothing leaves unless you say so")
                LaurelLine(title: "Not a TikTok app", detail: "No affiliation with TikTok")
            }
            .padding(.top, 8)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, Theme.margin)
    }
}
