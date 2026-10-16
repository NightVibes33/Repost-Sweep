import SwiftUI
import UIKit
import WebKit

struct FilledButton: View {
    var title: String
    var systemImage: String?
    var fill: Color
    var foreground: Color = .white
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(foreground.opacity(enabled ? 1 : 0.45))
            .background(enabled ? fill : Theme.raised)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
    }
}

struct PrimaryButton: View {
    var title: String
    var systemImage: String? = nil
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        FilledButton(
            title: title,
            systemImage: systemImage,
            fill: Theme.pink,
            foreground: .white,
            enabled: enabled,
            action: action
        )
    }
}

struct QuietButton: View {
    var title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
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
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct FreeMeter: View {
    var used: Int
    var limit: Int
    var subscribed: Bool
    var onUpgrade: () -> Void

    private var remaining: Int {
        max(0, limit - used)
    }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(subscribed ? "Premium" : "Free removals")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if subscribed {
                        Text("Unlimited")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.cyan)
                    } else {
                        Button("Upgrade") {
                            Haptics.tap()
                            onUpgrade()
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.pink)
                    }
                }
                if subscribed {
                    Text("The removal cap is off for this Apple ID.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                } else {
                    Text("\(remaining) of \(limit) left on this device")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.raised)
                            Capsule()
                                .fill(Theme.brand)
                                .frame(width: proxy.size.width * CGFloat(remaining) / CGFloat(max(limit, 1)))
                        }
                    }
                    .frame(height: 6)
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
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MarkView: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Theme.brand)
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(.black)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct AvatarView: View {
    var urlString: String
    var fallback: String
    var size: CGFloat = 44

    private var initial: String {
        let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    var body: some View {
        ZStack {
            Circle().fill(Theme.brand)
            Text(initial)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
            if let url = URL(string: urlString), url.scheme == "https" {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct ProgressRing: View {
    var progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.raised, lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(
                    Theme.brand,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.45, dampingFraction: 0.86), value: progress)
        }
        .accessibilityHidden(true)
    }
}

struct SweepErrorCard: View {
    var notice: SweepNotice
    var onRetry: () -> Void
    var onViewPage: () -> Void
    var onLogin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(notice.title, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .labelStyle(.titleAndIcon)
            Text(notice.message)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Retry", systemImage: "arrow.clockwise", action: onRetry)
            if notice.suggestLogin {
                Button("Log in again", action: onLogin)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.pink)
            }
            Button("View page", action: onViewPage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted.opacity(0.85))
            if let hint = notice.debugHint, hint.isEmpty == false {
                DisclosureGroup {
                    Text(hint)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .textSelection(.enabled)
                        .padding(.top, 6)
                } label: {
                    Text("Detail")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WebContainerView {
        WebContainerView(webView: webView)
    }

    func updateUIView(_ uiView: WebContainerView, context: Context) {
        uiView.attach(webView)
    }
}

final class WebContainerView: UIView {
    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        backgroundColor = .black
        attach(webView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        if webView.superview !== self {
            webView.removeFromSuperview()
            addSubview(webView)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        webView?.frame = bounds
    }
}
