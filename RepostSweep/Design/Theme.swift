import SwiftUI
import UIKit

enum Theme {
    static let canvas = Color.black
    static let surface = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    static let raised = Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
    static let ink = Color.white
    static let muted = Color(red: 161 / 255, green: 161 / 255, blue: 166 / 255)
    static let pink = Color(red: 254 / 255, green: 44 / 255, blue: 85 / 255)
    static let cyan = Color(red: 37 / 255, green: 244 / 255, blue: 238 / 255)
    static let accent = pink
    static let accentInk = Color.white
    static let danger = pink
    static let success = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    static let line = Color.white.opacity(0.08)

    static let brand = LinearGradient(
        colors: [cyan, pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum Typeface {
    static func display() -> Font {
        .system(size: 34, weight: .bold, design: .rounded)
    }

    static func title() -> Font {
        .system(size: 28, weight: .bold, design: .rounded)
    }

    static func headline() -> Font {
        .system(size: 20, weight: .semibold, design: .rounded)
    }

    static func body() -> Font {
        .system(size: 16, weight: .regular, design: .default)
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
