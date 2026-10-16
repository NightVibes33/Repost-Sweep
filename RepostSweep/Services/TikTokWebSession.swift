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
    @Published var showingDebugPage = false
    @Published var appLoginPhase: AppLoginPhase = .idle
    @Published var debugDetail = ""
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
    private var progressObservation: NSKeyValueObservation?
    private var activeObserver: AnyCancellable?
    private var resignObserver: AnyCancellable?
    private var didWarmUp = false
    private var didAdopt = false
    private var generation = 0
    private var loginGeneration = 0
    private var expectingHandoff = false
    private var didOpenHandoff = false
    private var didLeaveApp = false
    private var appLoginInFlight = false
    private var lastBlockedURL = ""
    private var lastHandoffReport = ""
    private var didReloadForReturn = false
    private var handoffWatch: Task<Void, Never>?
    private var returnWatch: Task<Void, Never>?
    private var loadingWatch: Task<Void, Never>?
    private var foregroundSliceStart: Date?
    private var foregroundAccumulated: TimeInterval = 0

    override init() {
        bridgeSource = Self.loadBridge()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        preferences.preferredContentMode = .mobile
        configuration.defaultWebpagePreferences = preferences
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
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
        let bridgeAtStart = WKUserScript(
            source: bridgeSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: world
        )
        configuration.userContentController.addUserScript(bridgeAtStart)
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
        activeObserver = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.appBecameActive()
            }
        resignObserver = NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.appWillResign()
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

    func cancelLogin() {
        loginGeneration += 1
        stopLoginWatch()
        expectingHandoff = false
        didOpenHandoff = false
        didLeaveApp = false
        appLoginInFlight = false
        appLoginPhase = .idle
        pageError = nil
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
        debugDetail = ""
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
        let api = await apiRemoval(itemId)
        if case .rateLimited = api { return api }
        if case .notLoggedIn = api { return api }
        switch await confirmRemoved(itemId) {
        case .gone:
            return .removed
        case .blocked(let attempt):
            return attempt
        case .stillThere:
            break
        }
        guard token == generation else { return .notLoggedIn }
        let tapped = await uiRemoval(itemId: itemId, prior: attemptDetail(api))
        if case .rateLimited = tapped { return tapped }
        if case .notLoggedIn = tapped { return tapped }
        switch await confirmRemoved(itemId) {
        case .gone:
            return .removed
        case .blocked(let attempt):
            return attempt
        case .stillThere:
            break
        }
        let prior = attemptDetail(tapped)
        let fallback = prior.isEmpty ? attemptDetail(api) : prior
        return .failed(fallback.isEmpty ? "Still on the repost list after both attempts." : "Still on the repost list. \(fallback)")
    }

    private func attemptDetail(_ attempt: RemovalAttempt) -> String {
        switch attempt {
        case .failed(let detail), .siteChanged(let detail):
            return detail
        case .removed:
            return ""
        case .rateLimited:
            return "RATE_LIMITED"
        case .notLoggedIn:
            return "NOT_LOGGED_IN"
        }
    }

    func noteDebug(_ text: String) {
        let clipped = String(text.prefix(500))
        guard clipped.isEmpty == false else { return }
        if debugDetail.isEmpty {
            debugDetail = clipped
        } else {
            debugDetail = clipped + "\n—\n" + debugDetail
        }
        if debugDetail.count > 4000 {
            debugDetail = String(debugDetail.prefix(4000))
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
        loginGeneration += 1
        let token = generation
        stopLoginWatch()
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
        debugDetail = ""
        showingDebugPage = false
        hasSessionCookie = false
        statusText = ""
        expectingHandoff = false
        didOpenHandoff = false
        didLeaveApp = false
        appLoginInFlight = false
        appLoginPhase = .idle
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: Date(timeIntervalSince1970: 0)
            ) {
                continuation.resume()
            }
        }
        guard token == generation else { return }
        webView.load(URLRequest(url: URL(string: "about:blank")!))
    }

    private func startLogin() async {
        loginGeneration += 1
        let token = loginGeneration
        stopLoginWatch()
        expectingHandoff = false
        didOpenHandoff = false
        didLeaveApp = false
        appLoginInFlight = false
        lastBlockedURL = ""
        lastHandoffReport = ""
        didReloadForReturn = false
        foregroundAccumulated = 0
        foregroundSliceStart = nil
        pageError = nil
        notice = nil
        appLoginPhase = .loading
        if await refreshSessionCookie() {
            guard token == loginGeneration else { return }
            adoptSession()
            return
        }
        guard token == loginGeneration else { return }
        expectingHandoff = true
        isPageLoading = true
        loginProgress = 0
        webView.customUserAgent = TikTokURL.mobileSafari
        webView.load(URLRequest(url: TikTokURL.login))
        armLoadingWatchdog(token: token)
    }

    private func stopLoginWatch() {
        handoffWatch?.cancel()
        returnWatch?.cancel()
        loadingWatch?.cancel()
        handoffWatch = nil
        returnWatch = nil
        loadingWatch = nil
    }

    private func armLoadingWatchdog(token: Int) {
        loadingWatch?.cancel()
        loadingWatch = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 28_000_000_000)
            guard Task.isCancelled == false else { return }
            guard token == self.loginGeneration else { return }
            guard self.appLoginPhase == .loading, self.didOpenHandoff == false, self.appLoginInFlight == false, self.handoffWatch == nil else { return }
            self.failLogin("TikTok’s login page didn’t load. Check the connection and retry.")
        }
    }

    private func triggerAppLogin() async {
        guard expectingHandoff, didOpenHandoff == false, appLoginInFlight == false else { return }
        let token = loginGeneration
        appLoginInFlight = true
        defer { appLoginInFlight = false }
        do {
            let envelope = try await invoke(.openAppLogin, payload: [:])
            guard token == loginGeneration, expectingHandoff else { return }
            if didOpenHandoff { return }
            if envelope.ok {
                if let url = handoffURL(in: envelope.message) {
                    handleExternalURL(url)
                }
                if didOpenHandoff == false {
                    scheduleHandoffTimeout(token: token, tapped: envelope.message)
                }
            } else {
                let message = envelope.message.isEmpty
                    ? "TikTok’s login page didn’t show Log in with TikTok app."
                    : envelope.message
                failLogin(message)
            }
        } catch {
            guard token == loginGeneration, expectingHandoff, didOpenHandoff == false else { return }
        }
    }

    private func handoffURL(in message: String) -> URL? {
        let schemes = ["tiktok://", "snssdk1233://", "snssdk1128://"]
        let lower = message.lowercased()
        for scheme in schemes {
            guard let range = lower.range(of: scheme) else { continue }
            let offset = lower.distance(from: lower.startIndex, to: range.lowerBound)
            let start = message.index(message.startIndex, offsetBy: offset)
            let tail = message[start...]
            let end = tail.firstIndex(where: { $0.isWhitespace }) ?? tail.endIndex
            let raw = String(tail[..<end]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”"))
            if let url = URL(string: raw), url.scheme != nil {
                return url
            }
        }
        return nil
    }

    private func scheduleHandoffTimeout(token: Int, tapped: String) {
        handoffWatch?.cancel()
        handoffWatch = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard Task.isCancelled == false else { return }
            guard token == self.loginGeneration, self.expectingHandoff, self.didOpenHandoff == false else { return }
            var message = "Tapped Log in with TikTok app, but no tiktok://, snssdk1233://, or snssdk1128:// link arrived."
            if tapped.isEmpty == false {
                message = "\(tapped) No tiktok://, snssdk1233://, or snssdk1128:// link arrived."
            }
            if self.lastBlockedURL.isEmpty == false {
                message += " Last non-web navigation: \(self.lastBlockedURL)."
            }
            self.failLogin(message)
        }
    }

    private func failLogin(_ message: String) {
        guard appLoginPhase == .loading || appLoginPhase == .waiting else { return }
        expectingHandoff = false
        didOpenHandoff = false
        stopLoginWatch()
        pageError = message
        appLoginPhase = .failed(message)
    }

    private func beginReturnWatch() {
        returnWatch?.cancel()
        foregroundAccumulated = 0
        foregroundSliceStart = UIApplication.shared.applicationState == .active ? Date() : nil
        let token = loginGeneration
        returnWatch = Task { @MainActor in
            while Task.isCancelled == false {
                if await self.refreshSessionCookie() {
                    self.adoptSession()
                    return
                }
                if self.foregroundElapsed() > 45 {
                    var message = self.didLeaveApp
                        ? "Returned from TikTok, but no session cookie (sessionid, sessionid_ss, or sid_tt) was set."
                        : "TikTok’s app link was opened, but this app stayed in the foreground and no session cookie (sessionid, sessionid_ss, or sid_tt) was set."
                    if self.lastHandoffReport.isEmpty == false {
                        message += " " + self.lastHandoffReport
                    }
                    self.failLogin(message)
                    return
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard token == self.loginGeneration, self.appLoginPhase == .waiting else { return }
            }
        }
    }

    private func foregroundElapsed() -> TimeInterval {
        var total = foregroundAccumulated
        if let start = foregroundSliceStart {
            total += Date().timeIntervalSince(start)
        }
        return total
    }

    func sceneBecameActive() {
        guard appLoginPhase == .waiting else { return }
        if foregroundSliceStart == nil {
            foregroundSliceStart = Date()
        }
        Task { await self.finishLoginOnReturn() }
    }

    func handleAuthCallback(_ url: URL) {
        guard url.scheme?.lowercased() == "repostsweep" else { return }
        guard appLoginPhase == .waiting || expectingHandoff else {
            noteDebug("Ignored \(url.absoluteString) because sign-in was not waiting.")
            return
        }
        expectingHandoff = false
        didOpenHandoff = true
        didLeaveApp = true
        appLoginPhase = .waiting
        handoffWatch?.cancel()
        loadingWatch?.cancel()
        if returnWatch == nil {
            beginReturnWatch()
        }
        noteDebug("TikTok returned to \(url.absoluteString)")
        Task { await self.finishLoginOnReturn() }
    }

    private func appBecameActive() {
        sceneBecameActive()
    }

    private func finishLoginOnReturn() async {
        let token = loginGeneration
        guard appLoginPhase == .waiting else { return }
        if await refreshSessionCookie() {
            adoptSession()
            return
        }
        guard token == loginGeneration, appLoginPhase == .waiting else { return }
        if didReloadForReturn == false {
            didReloadForReturn = true
            webView.customUserAgent = TikTokURL.mobileSafari
            webView.load(URLRequest(url: TikTokURL.home))
            await waitForSettle()
        }
        guard token == loginGeneration, appLoginPhase == .waiting else { return }
        if await refreshSessionCookie() {
            adoptSession()
        }
    }

    private func appWillResign() {
        guard appLoginPhase == .waiting || expectingHandoff else { return }
        didLeaveApp = true
        if let start = foregroundSliceStart {
            foregroundAccumulated += Date().timeIntervalSince(start)
            foregroundSliceStart = nil
        }
    }

    private func handleExternalURL(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        let handoff = scheme == "tiktok" || scheme == "snssdk1233" || scheme == "snssdk1128"
        guard expectingHandoff else { return }
        guard handoff else {
            lastBlockedURL = url.absoluteString
            return
        }
        guard didOpenHandoff == false else { return }
        let token = loginGeneration
        let rewritten = rewriteReturnURL(url)
        lastHandoffReport = rewritten.report
        noteDebug(rewritten.report)
        didOpenHandoff = true
        expectingHandoff = false
        handoffWatch?.cancel()
        loadingWatch?.cancel()
        appLoginPhase = .waiting
        beginReturnWatch()
        UIApplication.shared.open(rewritten.url, options: [:]) { success in
            Task { @MainActor in
                guard token == self.loginGeneration, self.appLoginPhase == .waiting else { return }
                guard success == false else { return }
                if UIApplication.shared.canOpenURL(rewritten.url) == false {
                    self.failLogin("The TikTok app isn’t installed, so \(scheme):// could not be opened.")
                } else {
                    self.failLogin("iOS could not open \(scheme)://.")
                }
            }
        }
    }

    private func rewriteReturnURL(_ url: URL) -> (url: URL, report: String) {
        let returnKeys: Set<String> = [
            "redirect_url", "redirect_uri", "redirect", "return_url", "returnurl",
            "next", "callback", "callback_url", "fallback_url", "web_url", "params_url"
        ]
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return (url, "Handoff URL could not be parsed. No query parameters were readable.")
        }
        let items = components.queryItems ?? []
        var notes: [String] = []
        var rewrote: [String] = []
        var updated = items
        for index in updated.indices {
            let name = updated[index].name
            let value = updated[index].value ?? ""
            let decoded = value.removingPercentEncoding ?? value
            let web = decoded.hasPrefix("http://") || decoded.hasPrefix("https://")
            if web && decoded.lowercased().contains("tiktok.com") {
                notes.append("\(name) (tiktok.com URL)")
            } else if name.isEmpty == false {
                notes.append(name)
            }
            guard returnKeys.contains(name.lowercased()), web else { continue }
            updated[index].value = "repostsweep://auth-callback"
            rewrote.append(name)
        }
        components.queryItems = updated.isEmpty ? nil : updated
        let rebuilt = components.url ?? url
        let listed = notes.isEmpty ? "(no query parameters)" : notes.joined(separator: ", ")
        let report: String
        if rewrote.isEmpty {
            report = "Handoff parameters: \(listed). None was a web return field this app could rewrite (redirect_url, next, return_url, and similar), so TikTok may only send you back to tiktok.com."
        } else {
            report = "Handoff parameters: \(listed). Rewrote \(rewrote.joined(separator: ", ")) to repostsweep://auth-callback."
        }
        return (rebuilt, report)
    }

    private func apiRemoval(_ itemId: String) async -> RemovalAttempt {
        do {
            let envelope = try await invoke(.remove, payload: ["itemId": itemId])
            let detail = envelope.message.isEmpty ? envelope.code : "\(envelope.code). \(envelope.message)"
            noteDebug(detail)
            switch envelope.code {
            case "RATE_LIMITED":
                return .rateLimited
            case "NOT_LOGGED_IN":
                return .notLoggedIn
            default:
                return .failed(detail)
            }
        } catch {
            let detail = "The unrepost request didn’t answer."
            noteDebug(detail)
            return .failed(detail)
        }
    }

    private enum VerifyResult {
        case gone
        case stillThere
        case blocked(RemovalAttempt)
    }

    private func confirmRemoved(_ itemId: String) async -> VerifyResult {
        do {
            let envelope = try await invoke(.confirmRemoved, payload: [
                "itemId": itemId,
                "secUid": account?.secUid ?? ""
            ])
            let detail = envelope.message.isEmpty ? envelope.code : envelope.message
            noteDebug(detail)
            if envelope.ok {
                return .gone
            }
            switch envelope.code {
            case "RATE_LIMITED":
                return .blocked(.rateLimited)
            case "NOT_LOGGED_IN":
                return .blocked(.notLoggedIn)
            default:
                return .stillThere
            }
        } catch {
            noteDebug("Couldn’t re-check the repost list.")
            return .stillThere
        }
    }

    private func uiRemoval(itemId: String, prior: String) async -> RemovalAttempt {
        let token = generation
        guard let uniqueId = account?.uniqueId, uniqueId.isEmpty == false else {
            return .failed(prior.isEmpty ? "No TikTok username to open the video." : prior)
        }
        guard let url = TikTokURL.video(uniqueId, itemId) else {
            return .failed(prior)
        }
        webView.load(URLRequest(url: url))
        await waitForSettle()
        guard token == generation else { return .notLoggedIn }
        do {
            let envelope = try await invoke(.unrepostTap, payload: ["itemId": itemId])
            let detail = envelope.message.isEmpty ? envelope.code : envelope.message
            noteDebug(detail)
            if envelope.code == "NOT_LOGGED_IN" {
                return .notLoggedIn
            }
            return .failed(detail)
        } catch {
            return .failed(prior.isEmpty ? "The video page didn’t answer." : prior)
        }
    }

    private func adoptSession() {
        let already = didAdopt
        didAdopt = true
        hasSessionCookie = true
        expectingHandoff = false
        didOpenHandoff = false
        stopLoginWatch()
        appLoginPhase = .idle
        pageError = nil
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
          thumbnail: async function () { return { ok: false, code: "BRIDGE_MISSING", message: "", dataURL: "" }; },
          openAppLogin: async function () { return { ok: false, code: "BRIDGE_MISSING", message: "TikTokBridge.js is missing from the app." }; },
          unrepostTap: async function () { return { ok: false, code: "BRIDGE_MISSING", message: "TikTokBridge.js is missing from the app." }; },
          confirmRemoved: async function () { return { ok: false, code: "BRIDGE_MISSING", message: "TikTokBridge.js is missing from the app." }; }
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
    case openAppLogin
    case unrepostTap
    case confirmRemoved
}

private enum TikTokURL {
    static let mobileSafari = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
    static let home = URL(string: "https://www.tiktok.com/")!
    static let login = URL(string: "https://www.tiktok.com/login?lang=en")!

    static func profile(_ uniqueId: String) -> URL? {
        guard let encoded = pathEncoded(uniqueId) else { return nil }
        return URL(string: "https://www.tiktok.com/@\(encoded)")
    }

    static func video(_ uniqueId: String, _ itemId: String) -> URL? {
        guard itemId.allSatisfy(\.isNumber), let encoded = pathEncoded(uniqueId) else { return nil }
        return URL(string: "https://www.tiktok.com/@\(encoded)/video/\(itemId)")
    }

    private static func pathEncoded(_ value: String) -> String? {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}

extension TikTokWebSession {
    enum AppLoginPhase: Equatable {
        case idle
        case loading
        case waiting
        case failed(String)
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
            if self.expectingHandoff && self.didOpenHandoff == false {
                if await self.refreshSessionCookie() {
                    self.adoptSession()
                    return
                }
                await self.triggerAppLogin()
                return
            }
            if await self.refreshSessionCookie() {
                if self.didAdopt == false || self.appLoginPhase == .waiting {
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
        if scheme == "http" || scheme == "https" || scheme == "about" || scheme.isEmpty {
            decisionHandler(.allow)
            return
        }
        let url = navigationAction.request.url
        decisionHandler(.cancel)
        if let url {
            Task { @MainActor in
                self.handleExternalURL(url)
            }
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            Task { @MainActor in
                self.webView.load(URLRequest(url: url))
            }
        } else if scheme.isEmpty == false {
            Task { @MainActor in
                self.handleExternalURL(url)
            }
        }
        return nil
    }

    nonisolated private func report(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
            return
        }
        Task { @MainActor in
            self.isPageLoading = false
            let host = self.webView.url?.host?.lowercased() ?? ""
            let loginStillLoading = self.expectingHandoff && self.didOpenHandoff == false && self.appLoginInFlight == false && self.handoffWatch == nil
            if loginStillLoading && host.contains("tiktok.com") == false {
                self.failLogin("TikTok’s login page didn’t load. Check the connection and retry.")
            } else if self.appLoginPhase == .idle {
                self.pageError = "TikTok didn’t load. Check the connection and reload."
            }
        }
    }
}
