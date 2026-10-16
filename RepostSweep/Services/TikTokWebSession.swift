import Combine
import ObjectiveC
import SwiftUI
import WebKit

/// Owns the single TikTok WKWebView. Passwords are never read. Session cookies
/// stay in the web view's data store and are not copied into app storage.
@MainActor
final class TikTokWebSession: NSObject, ObservableObject {
    let webView: WKWebView

    @Published var account: TikTokAccount?
    @Published var reposts: [RepostItem] = []
    @Published var isWorking = false
    @Published var statusText = ""
    @Published var banner: String?
    @Published var showingLogin = false
    @Published var isPageLoading = false
    @Published var pageError: String?
    @Published var siteChangeMessage: String?
    @Published var thumbnails: [String: UIImage] = [:]
    @Published var removalActive = false

    private let bridgeSource: String
    private let gate = JSGate()
    private var loginWatch: Task<Void, Never>?
    private var didWarmUp = false

    override init() {
        bridgeSource = Self.loadBridge()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        configuration.allowsInlineMediaPlayback = true
        let userScript = WKUserScript(
            source: bridgeSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: ScriptWorld.page
        )
        configuration.userContentController.addUserScript(userScript)
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.allowsBackForwardNavigationGestures = true
        webView = view
        super.init()
        view.navigationDelegate = self
        if #available(iOS 16.4, *) {
            view.isInspectable = true
        }
    }

    func warmUp() async {
        guard didWarmUp == false else { return }
        didWarmUp = true
        if webView.url == nil {
            webView.load(URLRequest(url: TikTokURL.home))
            await waitForSettle()
        }
        await refreshAccount()
    }

    func beginLogin() {
        pageError = nil
        showingLogin = true
        isPageLoading = true
        loginWatch?.cancel()
        webView.load(URLRequest(url: TikTokURL.login))
        loginWatch = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, self.showingLogin else { return }
                await self.refreshAccount()
            }
        }
    }

    func closeLogin() {
        showingLogin = false
        loginWatch?.cancel()
        loginWatch = nil
    }

    func reloadLogin() {
        pageError = nil
        isPageLoading = true
        webView.load(URLRequest(url: TikTokURL.login))
    }

    func refreshAccount() async {
        do {
            let envelope = try await invoke(.detect, payload: [:])
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
        isWorking = true
        banner = nil
        siteChangeMessage = nil
        statusText = "Checking the TikTok session…"
        defer { isWorking = false }

        await refreshAccount()
        guard var current = account, current.uniqueId.isEmpty == false else {
            statusText = ""
            beginLogin()
            return
        }

        if current.secUid.isEmpty {
            statusText = "Opening your profile…"
            await navigateToProfile(current.uniqueId)
            await refreshAccount()
            if let refreshed = account {
                current = refreshed
            }
        }

        var collected: [RepostItem] = []
        if current.secUid.isEmpty == false {
            let api = await collectFromAPI(into: &collected)
            if api.needsDom, collected.isEmpty {
                statusText = "Reading the reposts tab…"
                let dom = await scrapeDom(uniqueId: current.uniqueId)
                collected.append(contentsOf: dom.filter { item in
                    collected.contains(where: { $0.id == item.id }) == false
                })
                if collected.isEmpty {
                    siteChangeMessage = api.failureDetail ?? "ENDPOINT_CHANGED. The repost list no longer matches this version."
                } else {
                    banner = "TikTok’s list changed. These are the videos visible on your profile. Removal can still fail until the app is updated."
                }
            }
        } else {
            statusText = "Reading the reposts tab…"
            collected = await scrapeDom(uniqueId: current.uniqueId)
            if collected.isEmpty {
                siteChangeMessage = "NO_SEC_UID. TikTok didn’t include the account id this app uses to read reposts."
            }
        }

        reposts = collected
        statusText = collected.isEmpty ? "" : "\(collected.count) reposts"
    }

    func remove(itemId: String) async -> RemovalAttempt {
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

    func signOut() {
        loginWatch?.cancel()
        loginWatch = nil
        account = nil
        reposts = []
        thumbnails = [:]
        banner = nil
        siteChangeMessage = nil
        showingLogin = false
        statusText = ""
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) { }
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        didWarmUp = false
    }

    private struct APICollect {
        var needsDom: Bool
        var failureDetail: String?
    }

    private func collectFromAPI(into collected: inout [RepostItem]) async -> APICollect {
        var cursor = "0"
        var page = 0
        var keepGoing = true
        while keepGoing && page < 100 {
            page += 1
            statusText = "Reading reposts · \(collected.count) found"
            let envelope: BridgeEnvelope
            do {
                envelope = try await invoke(.list, payload: ["cursor": cursor, "mode": "api"])
            } catch {
                banner = "TikTok’s page didn’t answer. Check the connection and try again."
                reposts = collected
                return APICollect(needsDom: false, failureDetail: nil)
            }

            if envelope.ok == false {
                reposts = collected
                if envelope.code == "NOT_LOGGED_IN" {
                    beginLogin()
                    return APICollect(needsDom: false, failureDetail: nil)
                }
                if envelope.code == "RATE_LIMITED" {
                    banner = "TikTok asked for a pause. Reposts already loaded can still be removed."
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
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
        if page >= 100 && keepGoing {
            banner = "Loaded the first \(collected.count) reposts. Remove these, then scan again."
        }
        return APICollect(needsDom: false, failureDetail: nil)
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

/// The page-content world is `page` on older SDKs and `pageWorld` on newer ones.
/// Resolving it at runtime keeps the project building on either Xcode.
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
    static let home = URL(string: "https://www.tiktok.com/")!
    static let login = URL(string: "https://www.tiktok.com/login")!

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
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.isPageLoading = false
            if self.showingLogin {
                await self.refreshAccount()
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
