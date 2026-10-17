import SwiftUI
import UIKit

enum Theme {
    static let canvas = Color.black
    static let canvasRaised = Color(red: 11 / 255, green: 11 / 255, blue: 15 / 255)
    static let card = Color(red: 22 / 255, green: 22 / 255, blue: 28 / 255)
    static let surface = card
    static let raised = Color.white.opacity(0.06)
    static let ink = Color.white
    static let muted = Color.white.opacity(0.6)
    static let pink = Color(red: 254 / 255, green: 44 / 255, blue: 85 / 255)
    static let cyan = Color(red: 37 / 255, green: 244 / 255, blue: 238 / 255)
    static let accent = pink
    static let accentInk = Color.black
    static let danger = pink
    static let success = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    static let line = Color.white.opacity(0.06)

    static let radius: CGFloat = 20
    static let margin: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let buttonHeight: CGFloat = 56

    static let brand = LinearGradient(
        colors: [cyan, pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let ring = AngularGradient(
        colors: [cyan, pink, cyan],
        center: .center
    )
}

enum Typeface {
    static let hero = Font.system(size: 68, weight: .heavy, design: .rounded)
    static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let onboarding = Font.system(size: 30, weight: .bold, design: .rounded)
    static let title = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 17, weight: .regular, design: .rounded)
    static let secondary = Font.system(size: 15, weight: .regular, design: .rounded)
    static let caption = Font.system(size: 13, weight: .medium, design: .rounded)
    static let button = Font.system(size: 17, weight: .semibold, design: .rounded)
}

enum Motion {
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.8)
}

enum ScreenLayout {
    static var isNarrow: Bool {
        UIScreen.main.bounds.width <= 360
    }

    static var ring: CGFloat {
        isNarrow ? 176 : 230
    }

    static var onboardingRing: CGFloat {
        isNarrow ? 168 : 220
    }
}

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func burst() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

extension View {
    func readableColumn() -> some View {
        frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
    }

    func primaryGlow() -> some View {
        shadow(color: Theme.pink.opacity(0.42), radius: 18, y: 8)
            .shadow(color: Theme.cyan.opacity(0.22), radius: 10, y: 2)
    }

    @ViewBuilder
    func numericTextTransition() -> some View {
        if #available(iOS 17.0, *) {
            self.contentTransition(.numericText())
        } else {
            self
        }
    }

    @ViewBuilder
    func sweepSheetChrome() -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackground(Theme.canvas)
                .presentationCornerRadius(28)
        } else {
            self
        }
    }
}

struct ScreenBackdrop: View {
    var body: some View {
        ZStack {
            Theme.canvas
            Circle()
                .fill(Theme.cyan.opacity(0.16))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: -130, y: -280)
            Circle()
                .fill(Theme.pink.opacity(0.2))
                .frame(width: 260, height: 260)
                .blur(radius: 100)
                .offset(x: 150, y: -160)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct Shimmer: ViewModifier {
    @State private var move = false

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.16), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: geo.size.width * 0.45)
                    .rotationEffect(.degrees(18))
                    .offset(x: move ? geo.size.width : -geo.size.width)
                }
                .clipped()
            }
            .onAppear {
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    move = true
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(Shimmer())
    }
}
