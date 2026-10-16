import SwiftUI
import UIKit

enum Theme {
    static let canvas = dynamic(light: rgb(243, 245, 240), dark: rgb(20, 24, 21))
    static let surface = dynamic(light: rgb(255, 255, 255), dark: rgb(28, 34, 30))
    static let raised = dynamic(light: rgb(232, 236, 226), dark: rgb(39, 48, 42))
    static let ink = dynamic(light: rgb(18, 28, 22), dark: rgb(244, 246, 239))
    static let muted = dynamic(light: rgb(84, 97, 88), dark: rgb(183, 194, 184))
    static let accent = dynamic(light: rgb(190, 216, 32), dark: rgb(214, 242, 92))
    static let accentInk = Color(red: 20 / 255, green: 32 / 255, blue: 8 / 255)
    static let danger = dynamic(light: rgb(176, 48, 38), dark: rgb(255, 122, 104))
    static let line = dynamic(light: rgb(214, 220, 208), dark: rgb(58, 68, 60))

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
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

extension View {
    func readableColumn() -> some View {
        frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
    }
}
