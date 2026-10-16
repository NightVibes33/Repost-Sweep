import Combine
import ObjectiveC
import SwiftUI
import WebKit

/// Owns the single TikTok WKWebView. Passwords are never read. Session cookies
/// stay in the web view's data store. The app only checks whether a session
/// cookie name is present, and does not copy cookie values into its own storage.
@MainActor
final class TikTokWebSession: NSObject, ObservableObject {
    let webView: WKWebView

    @Published var account: TikTokAccount?
    @Published var reposts: [RepostItem] = []
    @Published var isWorking = false
    @Published var statusText = ""
    @Published var banner: String?
    @Published var showingLogin = false
    @Published var showingDebugPage = false
    @Published var isPageLoading = false
    @Published var loginProgress: Double = 0
    @Published var pageError: String?
    @Published var siteChangeMessage: String?
    @Published var notice: SweepNotice?
    @Published var thumbnails: [String: UIImage] = [:]
    @Published var removalActive = false
    @Published var hasSessionCookie = false
    @Published var didScan = false

    private let bridgeSource: String
    private let gate = JSGate()
    private var loginWatch: Task<Void, Never>?
    private var progressObservation: NSKeyValueObservation?
    private var didWarmUp = false
    private var didAdopt = false
    private var generation = 0

    override init() {
        bridgeSource = Self.loadBridge()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        preferences.preferredContentMode = .mobile
        configuration.defaultWebpagePreferences = preferences
        configuration.allowsInlineMediaPlayback = true
        let world = ScriptWorld.page
        let hideBanners = WKUserScript(
            source: Self.bannerHideScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: world
        )
        let hideBannersAgain = WKUserScript(
            source: Self.bannerHideScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: world
        )
        let bridge = WKUserScript(
            source: bridgeSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: world
        )
        configuration.userContentController.addUserScript(hideBanners)
        configuration.userContentController.addUserScript(hideBannersAgain)
        configuration.userContentController.addUserScript(bridge)
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = true
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.scrollView.indicatorStyle = .white
        view.scrollView.keyboardDismissMode = .interactive
        view.allowsBackForwardNavigationGestures = false
        view.allowsLinkPreview = false
        view.customUserAgent = TikTokURL.mobileSafari
        view.overrideUserInterfaceStyle = .dark
        webView = view
        super.init()
        view.navigationDelegate = self
        if #available(iOS 16.4, *) {
            view.isInspectable = true
        }
        progressObservation = view.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            let value = webView.estimatedProgress
            Task { @MainActor in
                self?.loginProgress = value
                if value > 0.04 {
                    self?.isPageLoading = value < 0.98
                }
            }
        }
    }

    func warmUp() async {
        guard didWarmUp == false else { return }
        didWarmUp = true
        guard await refreshSessionCookie() else { return }
        didAdopt = true
        await loadReposts()
    }

    func beginLogin() {
        Task { await startLogin() }
    }

    func closeLogin() {
        showingLogin = false
        loginWatch?.cancel()
        loginWatch = nil
    }

    func loginSheetDismissed() {
        loginWatch?.cancel()
        loginWatch = nil
        Task { @MainActor in
            if await self.refreshSessionCookie() {
                self.adoptSession()
            }
        }
    }

    func reloadLogin() {
        pageError = nil
        isPageLoading = true
        loginProgress = 0
        webView.load(URLRequest(url: TikTokURL.login))
    }

    func openDebugPage() {
        showingDebugPage = true
    }

    func refreshAccount() async {
        let token = generation
        do {
            let envelope = try await invoke(.detect, payload: [:])
            guard token == generation else { return }
            if let found = envelope.account, found.uniqueId.isEmpty == false {
                account = found
            } else if envelope.code == "NOT_LOGGED_IN" {
                account = nil
            }
        } catch {
            return
        }
    }

    func loadReposts() async {
        guard isWorking == false else { return }
        let token = generation
        let cookie = await refreshSessionCookie()
        guard token == generation else { return }
        let known = account?.uniqueId.isEmpty == false
        if cookie == false && known == false {
            statusText = ""
            return
        }

        isWorking = true
        banner = nil
        siteChangeMessage = nil
        notice = nil
        statusText = "Looking for reposts"
        defer {
            if token == generation {
                isWorking = false
                didScan = true
            }
        }

        await ensureHomePage()
        guard token == generation else { return }
        await refreshAccount()
        guard token == generation else { return }
        guard var current = account, current.uniqueId.isEmpty == false else {
            statusText = ""
            if cookie {
                notice = SweepNotice(
                    title: "Signed in, profile still loading",
                    message: "TikTok accepted the session, but didn’t share a username yet. Retry in a moment.",
                    debugHint: "NO_ACCOUNT",
                    suggestLogin: false
                )
            } else {
                notice = SweepNotice(
                    title: "TikTok doesn’t see the sign-in",
                    message: "The session looks expired. Log in again. Your password is never stored here.",
                    debugHint: "NOT_LOGGED_IN",
                    suggestLogin: true
                )
            }
            return
        }

        if current.secUid.isEmpty {
            statusText = "Opening your profile"
            await navigateToProfile(current.uniqueId)
            await refreshAccount()
            if let refreshed = account, refreshed.uniqueId.isEmpty == false {
                current = refreshed
            }
        }

        var collected: [RepostItem] = []
        if current.secUid.isEmpty == false {
            let api = await collectFromAPI(into: &collected)
            if api.needsDom, collected.isEmpty {
                statusText = "Reading the reposts tab"
                let dom = await scrapeDom(uniqueId: current.uniqueId)
                collected.append(contentsOf: dom.filter { item in
                    collected.contains(where: { $0.id == item.id }) == false
                })
                if collected.isEmpty {
                    notice = SweepNotice(
                        title: "TikTok changed this step",
                        message: "The repost list didn’t match what this version expects, so nothing was guessed. Retry, or check the page if it keeps happening.",
                        debugHint: api.failureDetail
                    )
                    siteChangeMessage = api.failureDetail
                } else {
                    banner = "TikTok’s list changed. These are the videos visible on your profile. Removal can still fail until the app is updated."
                }
            }
        } else {
            statusText = "Reading the reposts tab"
            collected = await scrapeDom(uniqueId: current.uniqueId)
            if collected.isEmpty {
                let detail = "NO_SEC_UID. TikTok didn’t include the account id this app uses to read reposts."
                siteChangeMessage = detail
                notice = SweepNotice(
                    title: "Couldn’t read the repost tab",
                    message: "TikTok didn’t include the account id this version needs. Retry, or look at the page to see what loaded.",
                    debugHint: detail
                )
            }
        }

        guard token == generation else { return }
        reposts = collected
        statusText = ""
    }

    func remove(itemId: String) async -> RemovalAttempt {
        let token = generation
        await ensureHomePage()
        guard token == generation else { return .notLoggedIn }
        do {
            let envelope = try await invoke(.remove, payload: ["itemId": itemId])
            if envelope.ok {
                return .removed
            }
            switch envelope.code {
            case "RATE_LIMITED":
                return .rateLimited
            case "NOT_LOGGED_IN":
                return .notLoggedIn
            case "ENDPOINT_CHANGED", "PARSE", "BRIDGE_MISSING", "NOT_ON_TIKTOK", "UI_CHANGED":
                let detail = envelope.message.isEmpty ? envelope.code : "\(envelope.code). \(envelope.message)"
                return .siteChanged(detail)
            default:
                let detail = envelope.message.isEmpty ? envelope.code : envelope.message
                return .failed(detail)
            }
        } catch {
            return .failed("The page didn’t answer.")
        }
    }

    func loadThumbnail(for item: RepostItem) async {
        guard thumbnails[item.id] == nil else { return }
        guard item.coverURL.isEmpty == false else { return }
        guard removalActive == false else { return }
        do {
            let envelope = try await invoke(.thumbnail, payload: [
                "itemId": item.id,
                "coverURL": item.coverURL
            ])
            guard Task.isCancelled == false, removalActive == false else { return }
            guard let image = Self.image(from: envelope.dataURL) else { return }
            thumbnails[item.id] = image
        } catch {
            return
        }
    }

    func signOut() async {
        generation += 1
        let token = generation
        loginWatch?.cancel()
        loginWatch = nil
        didAdopt = false
        isWorking = false
        didScan = false
        didWarmUp = false
        account = nil
        reposts = []
        thumbnails = [:]
        banner = nil
        siteChangeMessage = nil
        notice = nil
        showingLogin = false
        showingDebugPage = false
        hasSessionCookie = false
        statusText = ""
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: Date(timeIntervalSince1970: 0)
            ) {
                continuation.resume()
            }
        }
        guard token == generation else { return }
        if showingLogin {
            webView.load(URLRequest(url: TikTokURL.login))
        } else {
            webView.load(URLRequest(url: URL(string: "about:blank")!))
        }
    }

    private func startLogin() async {
        if await refreshSessionCookie() {
            adoptSession()
            return
        }
        pageError = nil
        notice = nil
        isPageLoading = true
        loginProgress = 0
        showingLogin = true
        webView.customUserAgent = TikTokURL.mobileSafari
        webView.load(URLRequest(url: TikTokURL.login))
        loginWatch?.cancel()
        loginWatch = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.showingLogin else { return }
                if await self.refreshSessionCookie() {
                    self.adoptSession()
                    return
                }
            }
        }
    }

    private func adoptSession() {
        let already = didAdopt
        didAdopt = true
        hasSessionCookie = true
        showingLogin = false
        loginWatch?.cancel()
        loginWatch = nil
        guard already == false else { return }
        Haptics.success()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard Task.isCancelled == false else { return }
            await self.loadReposts()
        }
    }

    @discardableResult
    private func refreshSessionCookie() async -> Bool {
        let cookies = await withCheckedContinuation { (continuation: CheckedContinuation<[HTTPCookie], Never>) in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        let found = cookies.contains { cookie in
            guard cookie.domain.lowercased().contains("tiktok.com") else { return false }
            switch cookie.name.lowercased() {
            case "sessionid", "sessionid_ss", "sid_tt":
                return true
            default:
                return false
            }
        }
        hasSessionCookie = found
        return found
    }

    private func ensureHomePage() async {
        let host = webView.url?.host?.lowercased() ?? ""
        let path = webView.url?.path.lowercased() ?? ""
        let onSite = host.contains("tiktok.com")
        let onLogin = path.contains("login")
        if onSite == false || onLogin || webView.url == nil {
            webView.load(URLRequest(url: TikTokURL.home))
            await waitForSettle()
        }
    }

    private func hideLoginPromos() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            webView.evaluateJavaScript(Self.loginChromeScript) { _, _ in
                continuation.resume()
            }
        }
    }

    private struct APICollect {
        var needsDom: Bool
        var failureDetail: String?
    }

    private func collectFromAPI(into collected: inout [RepostItem]) async -> APICollect {
        var cursor = "0"
        var page = 0
        var keepGoing = true
        let token = generation
        while keepGoing && page < 100 {
            guard token == generation else {
                return APICollect(needsDom: false, failureDetail: nil)
            }
            page += 1
            statusText = collected.isEmpty ? "Looking for reposts" : "\(collected.count) found"
            guard let envelope = await listPage(cursor: cursor) else {
                guard token == generation else {
                    return APICollect(needsDom: false, failureDetail: nil)
                }
                reposts = collected
                if collected.isEmpty {
                    notice = SweepNotice(
                        title: "Couldn’t reach TikTok",
                        message: "The repost list didn’t load. Check the connection and retry. Your sign-in stays on this device.",
                        debugHint: "NETWORK"
                    )
                } else {
                    banner = "The scan stopped early. You can still remove the \(collected.count) already listed."
                }
                return APICollect(needsDom: false, failureDetail: "NETWORK")
            }
            guard token == generation else {
                return APICollect(needsDom: false, failureDetail: nil)
            }

            if envelope.ok == false {
                reposts = collected
                if envelope.code == "NOT_LOGGED_IN" {
                    notice = SweepNotice(
                        title: "TikTok doesn’t see the sign-in",
                        message: "The session looks expired. Log in again, then retry.",
                        debugHint: envelope.message.isEmpty ? envelope.code : envelope.message,
                        suggestLogin: true
                    )
                    return APICollect(needsDom: false, failureDetail: nil)
                }
                if envelope.code == "RATE_LIMITED" {
                    notice = SweepNotice(
                        title: "TikTok asked for a pause",
                        message: "Too many requests just now. Wait a moment, then retry. Reposts already listed can still be removed.",
                        debugHint: envelope.message.isEmpty ? "RATE_LIMITED" : envelope.message
                    )
                    return APICollect(needsDom: false, failureDetail: nil)
                }
                if envelope.code == "EMPTY" {
                    return APICollect(needsDom: false, failureDetail: nil)
                }
                let detail = envelope.message.isEmpty ? envelope.code : "\(envelope.code). \(envelope.message)"
                if collected.isEmpty {
                    return APICollect(needsDom: true, failureDetail: detail)
                }
                banner = "The scan stopped early. You can still remove the \(collected.count) already listed."
                return APICollect(needsDom: false, failureDetail: detail)
            }

            for item in envelope.items where item.id.isEmpty == false && collected.contains(where: { $0.id == item.id }) == false {
                collected.append(item)
            }
            reposts = collected
            let next = envelope.cursor
            if envelope.hasMore == false || next.isEmpty || next == cursor {
                keepGoing = false
            } else {
                cursor = next
                await pause(0.7...1.3)
            }
        }
        if page >= 100 && keepGoing {
            banner = "Loaded the first \(collected.count) reposts. Remove these, then scan again."
        }
        return APICollect(needsDom: false, failureDetail: nil)
    }

    private func listPage(cursor: String) async -> BridgeEnvelope? {
        var delay: Double = 0
        for attempt in 0..<3 {
            if delay > 0 {
                await pause(delay...delay)
            }
            do {
                let envelope = try await invoke(.list, payload: [
                    "cursor": cursor,
                    "mode": "api",
                    "secUid": account?.secUid ?? ""
                ])
                if envelope.code == "NETWORK" || envelope.code == "BRIDGE_MISSING" {
                    delay = 1.2 * Double(attempt + 1)
                    continue
                }
                return envelope
            } catch {
                delay = 1.2 * Double(attempt + 1)
            }
        }
        return nil
    }

    private func scrapeDom(uniqueId: String) async -> [RepostItem] {
        await navigateToProfile(uniqueId)
        let focused = try? await invoke(.focusReposts, payload: [:])
        guard focused?.ok == true else {
            return []
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        var found: [RepostItem] = []
        for _ in 0..<6 {
            if let envelope = try? await invoke(.list, payload: ["mode": "dom", "cursor": "0"]), envelope.ok {
                for item in envelope.items where item.id.isEmpty == false && found.contains(where: { $0.id == item.id }) == false {
                    found.append(item)
                }
            }
            _ = try? await invoke(.scrollPage, payload: [:])
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
        return found
    }

    private func navigateToProfile(_ uniqueId: String) async {
        guard let url = TikTokURL.profile(uniqueId) else { return }
        webView.load(URLRequest(url: url))
        await waitForSettle()
    }

    private func waitForSettle() async {
        try? await Task.sleep(nanoseconds: 400_000_000)
        let start = Date()
        while webView.isLoading && Date().timeIntervalSince(start) < 20 {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        try? await Task.sleep(nanoseconds: 700_000_000)
    }

    private func pause(_ range: ClosedRange<Double>) async {
        let seconds = Double.random(in: range)
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func invoke(_ call: BridgeCall, payload: [String: Any]) async throws -> BridgeEnvelope {
        await gate.acquire()
        do {
            if call == .thumbnail && removalActive {
                await gate.release()
                return .skipped()
            }
            var envelope = try await evaluate(call, payload: payload)
            if envelope.code == "BRIDGE_MISSING" {
                try? await reinjectBridge()
                envelope = try await evaluate(call, payload: payload)
            }
            await gate.release()
            return envelope
        } catch {
            await gate.release()
            throw error
        }
    }

    private func evaluate(_ call: BridgeCall, payload: [String: Any]) async throws -> BridgeEnvelope {
        let body = """
        if (!window.__repostSweep || typeof window.__repostSweep.\(call.rawValue) !== "function") {
          return { ok: false, code: "BRIDGE_MISSING", message: "TikTok page is not ready." };
        }
        const result = await window.__repostSweep.\(call.rawValue)(payload);
        return result || { ok: false, code: "BRIDGE_MISSING", message: "Empty result." };
        """
        let value = try await webView.callAsyncJavaScript(
            body,
            arguments: ["payload": payload],
            in: nil,
            contentWorld: ScriptWorld.page
        )
        guard let value else {
            throw SessionError.emptyResult
        }
        return try Self.decodeEnvelope(value)
    }

    private func reinjectBridge() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webView.evaluateJavaScript(bridgeSource) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func decodeEnvelope(_ value: Any) throws -> BridgeEnvelope {
        guard JSONSerialization.isValidJSONObject(value) else {
            throw SessionError.badPayload
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        return try JSONDecoder().decode(BridgeEnvelope.self, from: data)
    }

    private static func image(from dataURL: String) -> UIImage? {
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        let encoded = String(dataURL[dataURL.index(after: comma)...])
        guard let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return UIImage(data: data)
    }

    private static let bannerHideScript = """
    (function () {
      var css = '[data-e2e="cookie-banner"],[class*="CookieBanner"],[class*="cookie-banner"],[class*="DivOpenApp"],[class*="OpenApp"],[data-e2e="bottom-cta"],[class*="AppDownload"],[class*="DownloadBar"],[class*="smart-banner"],[class*="SmartBanner"],a[href*="apps.apple.com"],[data-e2e="open-in-app"],[class*="BottomBanner"],[class*="PromoteApp"],[id*="pns-communication"]{display:none!important;height:0!important;overflow:hidden!important;pointer-events:none!important;}';
      function apply() {
        var node = document.getElementById("repost-sweep-banner-css");
        if (!node) {
          node = document.createElement("style");
          node.id = "repost-sweep-banner-css";
          (document.head || document.documentElement).appendChild(node);
        }
        node.textContent = css;
      }
      apply();
    })();
    """

    private static let loginChromeScript = """
    (function () {
      var css = 'header,[data-e2e="top-bar"],[class*="DivHeaderContainer"],[class*="HeaderContainer"],#app-header,[data-e2e="cookie-banner"],[class*="CookieBanner"],[class*="DivOpenApp"],[class*="OpenApp"],[data-e2e="bottom-cta"],[class*="AppDownload"],[class*="DownloadBar"],a[href*="apps.apple.com"],[class*="BottomBanner"]{display:none!important;}';
      var node = document.getElementById("repost-sweep-login-chrome");
      if (!node) {
        node = document.createElement("style");
        node.id = "repost-sweep-login-chrome";
        (document.head || document.documentElement).appendChild(node);
      }
      node.textContent = css;
    })();
    """

    private static func loadBridge() -> String {
        let url = Bundle.main.url(forResource: "TikTokBridge", withExtension: "js")
            ?? Bundle.main.url(forResource: "TikTokBridge", withExtension: "js", subdirectory: "Resources")
        if let url, let text = try? String(contentsOf: url, encoding: .utf8), text.isEmpty == false {
            return text
        }
        return """
        window.__repostSweep = {
          detect: async function () { return { ok: false, code: "BRIDGE_MISSING", message: "TikTokBridge.js is missing from the app." }; },
          list: async function () { return { ok: false, code: "BRIDGE_MISSING", message: "TikTokBridge.js is missing from the app." }; },
          remove: async function () { return { ok: false, code: "BRIDGE_MISSING", message: "TikTokBridge.js is missing from the app." }; },
          focusReposts: async function () { return { ok: false, code: "BRIDGE_MISSING", message: "" }; },
          scrollPage: async function () { return { ok: false, code: "BRIDGE_MISSING", message: "" }; },
          thumbnail: async function () { return { ok: false, code: "BRIDGE_MISSING", message: "", dataURL: "" }; }
        };
        """
    }
}

private enum ScriptWorld {
    static var page: WKContentWorld {
        if let world = classProperty("pageWorld") ?? classProperty("page") {
            return world
        }
        preconditionFailure("WKContentWorld has no page world")
    }

    private static func classProperty(_ name: String) -> WKContentWorld? {
        let selector = NSSelectorFromString(name)
        guard let method = class_getClassMethod(WKContentWorld.self, selector) else {
            return nil
        }
        typealias Getter = @convention(c) (AnyClass, Selector) -> Unmanaged<WKContentWorld>
        let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        return getter(WKContentWorld.self, selector).takeUnretainedValue()
    }
}

private enum BridgeCall: String {
    case detect
    case list
    case remove
    case focusReposts
    case scrollPage
    case thumbnail
}

private enum TikTokURL {
    static let mobileSafari = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
    static let home = URL(string: "https://www.tiktok.com/")!
    static let login = URL(string: "https://www.tiktok.com/login?lang=en")!

    static func profile(_ uniqueId: String) -> URL? {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let encoded = uniqueId.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: "https://www.tiktok.com/@\(encoded)")
    }
}

private actor JSGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if busy == false {
            busy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}

extension TikTokWebSession: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            self.isPageLoading = true
            self.pageError = nil
            self.loginProgress = 0.08
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.isPageLoading = false
            self.loginProgress = 1
            guard self.showingLogin else { return }
            await self.hideLoginPromos()
            if await self.refreshSessionCookie() {
                self.adoptSession()
                return
            }
            let path = webView.url?.path.lowercased() ?? ""
            let host = webView.url?.host?.lowercased() ?? ""
            if host.contains("tiktok.com"), path.contains("login") == false {
                await self.refreshAccount()
                if self.account?.uniqueId.isEmpty == false {
                    self.adoptSession()
                }
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        report(error)
    }

    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" || scheme == "about" {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            Task { @MainActor in
                self.webView.load(URLRequest(url: url))
            }
        }
        return nil
    }

    nonisolated private func report(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        Task { @MainActor in
            self.isPageLoading = false
            self.pageError = "TikTok didn’t load. Check the connection and reload."
        }
    }
}
