import SwiftUI
import WebKit

struct PrimaryButton: View {
    var title: String
    var systemImage: String?
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(Theme.accentInk)
            .background(enabled ? Theme.accent : Theme.raised)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .accessibilityAddTraits(.isButton)
    }
}

struct QuietButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .foregroundStyle(Theme.ink)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                )
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct SurfaceCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}

struct FreeMeter: View {
    var used: Int
    var limit: Int
    var subscribed: Bool

    private var remaining: Int {
        max(0, limit - used)
    }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(subscribed ? "Unlimited" : "Free tier")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .textCase(.uppercase)
                    Spacer()
                    if subscribed {
                        Text("Active")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.accentInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                    }
                }
                if subscribed {
                    Text("Your subscription clears the removal cap.")
                        .font(Typeface.body())
                        .foregroundStyle(Theme.ink)
                } else {
                    Text("\(remaining) of \(limit) free removals left on this device")
                        .font(Typeface.body())
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.raised)
                            Capsule()
                                .fill(Theme.accent)
                                .frame(width: proxy.size.width * CGFloat(remaining) / CGFloat(max(limit, 1)))
                        }
                    }
                    .frame(height: 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(remaining) free removals remaining")
                }
            }
        }
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
