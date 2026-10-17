import SwiftUI
import UIKit
import WebKit

struct FilledButton: View {
    var title: String
    var systemImage: String?
    var fill: Color
    var foreground: Color = .white
    var enabled: Bool = true
    var glowing: Bool = false
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
                    .font(Typeface.button)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .numericTextTransition()
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.buttonHeight)
            .foregroundStyle(foreground.opacity(enabled ? 1 : 0.45))
            .background(enabled ? fill : Theme.raised)
            .clipShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .primaryGlowIf(glowing && enabled)
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
            fill: .white,
            foreground: .black,
            enabled: enabled,
            glowing: true,
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
                    .font(Typeface.button)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.buttonHeight)
            .foregroundStyle(Theme.ink)
            .background(Theme.card)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct SurfaceCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
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
        Button {
            Haptics.tap()
            onUpgrade()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.brand)
                    .frame(width: 8, height: 8)
                Text(subscribed ? "Premium · Unlimited" : "\(remaining) free left")
                    .numericTextTransition()
                if subscribed == false {
                    Text("Upgrade")
                        .foregroundStyle(Theme.pink)
                }
            }
            .font(Typeface.caption)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(subscribed ? "Premium, unlimited removals" : "\(remaining) free removals left. Upgrade.")
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(Motion.spring, value: configuration.isPressed)
    }
}

struct AppGlyph: View {
    var size: CGFloat = 88

    var body: some View {
        Image("AppMark")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct MarkView: View {
    var size: CGFloat = 28

    var body: some View {
        AppGlyph(size: size)
    }
}

struct TikTokMark: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Image(systemName: "music.note")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Theme.cyan)
                .offset(x: -1.2, y: -1)
            Image(systemName: "music.note")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Theme.pink)
                .offset(x: 1.2, y: 1)
            Image(systemName: "music.note")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size + 6, height: size + 6)
        .accessibilityHidden(true)
    }
}

struct ContinueWithTikTokButton: View {
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .bold))
                Text("Continue with TikTok")
                    .font(Typeface.button)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.buttonHeight)
            .foregroundStyle(.black)
            .background(Color.white)
            .clipShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .primaryGlow()
        .accessibilityLabel("Continue with TikTok")
    }
}

struct TikTokLoginControl: View {
    var phase: TikTokWebSession.AppLoginPhase
    var finishing: Bool = false
    var onStart: () -> Void
    var onCancel: () -> Void

    var body: some View {
        switch phase {
        case .idle:
            ContinueWithTikTokButton(action: onStart)
        case .loading:
            waiting(title: "Opening TikTok…")
        case .waiting:
            waiting(title: finishing ? "Finishing sign-in…" : "Waiting for TikTok…")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    Text(message)
                        .font(Typeface.secondary)
                        .foregroundStyle(Theme.pink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 180)
                PrimaryButton(title: "Retry", systemImage: "arrow.clockwise", action: onStart)
            }
        }
    }

    private func waiting(title: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Theme.ink)
            Text(title)
                .font(Typeface.secondary)
                .foregroundStyle(Theme.ink)
            Button("Cancel", action: onCancel)
                .font(Typeface.secondary)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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
            Circle().fill(Theme.card)
            Text(initial)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            if let url = AvatarView.allowedURL(urlString) {
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
        .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityHidden(true)
    }

    private static func allowedURL(_ urlString: String) -> URL? {
        let lower = urlString.lowercased()
        if lower.contains("googleusercontent")
            || lower.contains("ggpht")
            || lower.contains("google.com")
            || lower.contains("gstatic")
            || lower.contains("fbcdn") {
            return nil
        }
        guard let url = URL(string: urlString), url.scheme == "https" else { return nil }
        return url
    }
}

struct MetricRing<Center: View>: View {
    var progress: Double?
    @ViewBuilder var center: Center

    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.raised, lineWidth: 12)
            ring
            center
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }

    @ViewBuilder
    private var ring: some View {
        if let progress {
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(Theme.ring, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.spring, value: progress)
                .shadow(color: Theme.cyan.opacity(0.35), radius: 8)
                .shadow(color: Theme.pink.opacity(0.28), radius: 10)
        } else {
            Circle()
                .trim(from: 0.05, to: 0.28)
                .stroke(Theme.ring, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .shadow(color: Theme.cyan.opacity(0.35), radius: 8)
        }
    }
}

struct RollingNumber: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(Int(value.rounded()).formatted(.number.grouping(.automatic)))
            .font(Typeface.hero)
            .foregroundStyle(Theme.ink)
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .numericTextTransition()
    }
}

struct CoverImage: View {
    var urlString: String
    var fallback: UIImage?
    var width: CGFloat = 64
    var height: CGFloat = 84

    var body: some View {
        ZStack {
            Theme.canvasRaised
            Image(systemName: "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.muted)
            if let fallback {
                Image(uiImage: fallback)
                    .resizable()
                    .scaledToFill()
            }
            if let url = CoverImage.httpsURL(urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        Theme.canvasRaised
                            .shimmering()
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private static func httpsURL(_ urlString: String) -> URL? {
        guard let url = URL(string: urlString), url.scheme == "https" else { return nil }
        return url
    }
}

struct StatusChip: View {
    var title: String
    var active: Bool = false

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(active ? Theme.pink : Theme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(active ? Theme.pink.opacity(0.14) : Theme.raised, in: Capsule())
    }
}

struct SelectionCircle: View {
    var selected: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(selected ? Theme.pink : Theme.muted, lineWidth: 1.5)
                .background(Circle().fill(selected ? Theme.pink : Color.clear))
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 26, height: 26)
        .animation(Motion.spring, value: selected)
        .accessibilityHidden(true)
    }
}

struct LaurelLine: View {
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "laurel.leading")
                .font(.system(size: 28, weight: .light))
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(detail)
                    .font(Typeface.caption)
                    .foregroundStyle(Theme.muted)
            }
            Image(systemName: "laurel.trailing")
                .font(.system(size: 28, weight: .light))
        }
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .combine)
    }
}

struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.raised)
                .frame(width: 64, height: 84)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.raised)
                    .frame(width: 160, height: 14)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.raised)
                    .frame(width: 96, height: 12)
            }
            Spacer()
        }
        .padding(Theme.cardPadding)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .shimmering()
        .accessibilityHidden(true)
    }
}

struct PageDots: View {
    var count: Int
    var index: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { item in
                Capsule()
                    .fill(item == index ? Theme.ink : Theme.raised)
                    .frame(width: item == index ? 22 : 8, height: 8)
            }
        }
        .animation(Motion.spring, value: index)
        .accessibilityHidden(true)
    }
}

struct SweepErrorCard: View {
    var notice: SweepNotice
    var onRetry: () -> Void
    var onViewPage: () -> Void
    var onLogin: () -> Void

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(notice.title, systemImage: "exclamationmark.triangle.fill")
                    .font(Typeface.secondary)
                    .foregroundStyle(Theme.ink)
                    .labelStyle(.titleAndIcon)
                Text(notice.message)
                    .font(Typeface.secondary)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "Retry", systemImage: "arrow.clockwise", action: onRetry)
                if notice.suggestLogin {
                    Button("Log in again", action: onLogin)
                        .font(Typeface.secondary)
                        .foregroundStyle(Theme.pink)
                }
                Button("View page", action: onViewPage)
                    .font(Typeface.caption)
                    .foregroundStyle(Theme.muted)
                if let hint = notice.debugHint, hint.isEmpty == false {
                    DisclosureGroup {
                        Text(hint)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .textSelection(.enabled)
                            .padding(.top, 6)
                    } label: {
                        Text("Detail")
                            .font(Typeface.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }
}

struct RepostCard: View {
    var item: RepostItem
    var image: UIImage?
    var selected: Bool
    var active: Bool
    var showsSelection: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                CoverImage(urlString: item.coverURL, fallback: image)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.titleLine)
                        .font(Typeface.secondary)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if item.author.isEmpty == false {
                        Text("@\(item.author)")
                            .font(Typeface.caption)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    StatusChip(title: active ? "Removing" : "Repost", active: active)
                }
                Spacer(minLength: 8)
                if showsSelection {
                    SelectionCircle(selected: selected)
                }
            }
            .padding(Theme.cardPadding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(selected || active ? Theme.pink.opacity(0.85) : Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(item.titleLine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct IconChip: View {
    var systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(Theme.card, in: Circle())
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct BottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 8) {
            content
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .background(Theme.canvas.opacity(0.72))
        .readableColumn()
    }
}

private extension View {
    @ViewBuilder
    func primaryGlowIf(_ enabled: Bool) -> some View {
        if enabled {
            self.primaryGlow()
        } else {
            self
        }
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
