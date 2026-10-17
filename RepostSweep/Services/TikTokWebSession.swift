import AVFoundation
import Combine
import ObjectiveC
import os
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
    @Published var showLoginSuccess = false
    @Published var isFinishingReturn = false

    private let bridgeSource: String
    private let handoffLog = Logger(subsystem: "app.repostsweep.ios", category: "handoff")
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
        configuration.allowsInlineMediaPlayback = false
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
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
        let silence = WKUserScript(
            source: Self.silenceScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: world
        )
        configuration.userContentController.addUserScript(silence)
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
        silencePlayback(on: view)
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
        isFinishingReturn = false
        showLoginSuccess = false
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
        let preservedHandoff = lastHandoffReport
        debugDetail = preservedHandoff
        statusText = "Looking for reposts"
        defer {
            if token == generation {
                isWorking = false
                didScan = true
                self.parkWebView()
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
        silencePlayback(on: webView)
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

    func noteDebug(_ text: String, limit: Int = 500) {
        let clipped = String(text.prefix(max(1, limit)))
        guard clipped.isEmpty == false else { return }
        if debugDetail.isEmpty {
            debugDetail = clipped
        } else {
            debugDetail = clipped + "\n—\n" + debugDetail
        }
        if debugDetail.count > 16000 {
            debugDetail = String(debugDetail.prefix(16000))
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
        isFinishingReturn = false
        showLoginSuccess = false
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
            if envelope.message.isEmpty == false {
                noteDebug("Bridge login result: \(envelope.message)", limit: 8000)
                logHandoffLine("bridge", envelope.message)
            }
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
        isFinishingReturn = false
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
        silencePlayback(on: webView)
        switch appLoginPhase {
        case .waiting:
            break
        case .failed(_) where didLeaveApp:
            appLoginPhase = .waiting
            if returnWatch == nil {
                beginReturnWatch()
            }
        default:
            return
        }
        if foregroundSliceStart == nil {
            foregroundSliceStart = Date()
        }
        isFinishingReturn = true
        noteDebug("App became active during sign-in. Polling for a session with no extra tap.")
        logHandoffLine("active", "became active while waiting. \(lastHandoffReport)")
        Task { await self.finishLoginOnReturn() }
    }

    func handleAuthCallback(_ url: URL) {
        guard Self.isAuthReturn(url) else { return }
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
        isFinishingReturn = true
        for _ in 0..<8 {
            if await refreshSessionCookie() {
                adoptSession()
                return
            }
            guard token == loginGeneration, appLoginPhase == .waiting else { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard token == loginGeneration, appLoginPhase == .waiting else { return }
        if didReloadForReturn == false {
            didReloadForReturn = true
            noteDebug("No session cookie yet. Reloading tiktok.com once and polling again.")
            webView.customUserAgent = TikTokURL.mobileSafari
            silencePlayback(on: webView)
            webView.load(URLRequest(url: TikTokURL.home))
            await waitForSettle()
            silencePlayback(on: webView)
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
        logHandoffLine("captured", url.absoluteString)
        let rewritten = rewriteReturnURL(url)
        lastHandoffReport = rewritten.report
        noteDebug(rewritten.report, limit: 12000)
        logHandoffLine("rewritten", rewritten.url.absoluteString)
        logHandoffLine("report", rewritten.report)
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
        HandoffRewriter.rewrite(url)
    }

    private func logHandoffLine(_ label: String, _ text: String) {
        let body = text.isEmpty ? "(empty)" : text
        let size = 700
        var start = body.startIndex
        var index = 0
        var total = 1
        if body.count > size {
            total = (body.count + size - 1) / size
        }
        while start < body.endIndex {
            let end = body.index(start, offsetBy: size, limitedBy: body.endIndex) ?? body.endIndex
            let chunk = String(body[start..<end])
            let part = index + 1
            handoffLog.info("\(label, privacy: .public) [\(part)/\(total)] \(chunk, privacy: .public)")
            start = end
            index += 1
        }
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
        let celebrate = appLoginPhase == .waiting || didLeaveApp || isFinishingReturn
        let already = didAdopt
        didAdopt = true
        hasSessionCookie = true
        expectingHandoff = false
        didOpenHandoff = false
        didLeaveApp = false
        isFinishingReturn = false
        stopLoginWatch()
        appLoginPhase = .idle
        pageError = nil
        silencePlayback(on: webView)
        guard already == false else { return }
        if celebrate {
            showLoginSuccess = true
        }
        Haptics.success()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard Task.isCancelled == false else { return }
            await self.loadReposts()
        }
    }

    private func silencePlayback(on view: WKWebView) {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.ambient, options: [.mixWithOthers])
        try? audio.setActive(true)
        view.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        view.evaluateJavaScript("window.__repostSweepSilence&&window.__repostSweepSilence()") { _, _ in }
    }

    private static func isAuthReturn(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "repostsweep" { return true }
        if scheme == "https" || scheme == "http" {
            let host = url.host?.lowercased() ?? ""
            let path = url.path.lowercased()
            if host == "repostsweep.app" && path.contains("auth-callback") {
                return true
            }
        }
        return false
    }

    func parkWebView() {
        silencePlayback(on: webView)
        guard showingDebugPage == false else { return }
        guard removalActive == false, isWorking == false else { return }
        switch appLoginPhase {
        case .loading, .waiting:
            return
        default:
            break
        }
        let current = webView.url?.absoluteString ?? ""
        if current.isEmpty || current == "about:blank" { return }
        webView.stopLoading()
        webView.load(URLRequest(url: URL(string: "about:blank")!))
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

    private static let silenceScript = """
    (function () {
      function mute(el) {
        try {
          el.muted = true;
          el.defaultMuted = true;
          el.volume = 0;
          if (typeof el.pause === "function") el.pause();
        } catch (error) {}
      }
      function scan(root) {
        if (!root || !root.querySelectorAll) return;
        var nodes = root.querySelectorAll("video, audio");
        for (var i = 0; i < nodes.length; i += 1) mute(nodes[i]);
      }
      var proto = window.HTMLMediaElement && HTMLMediaElement.prototype;
      if (proto && !proto.__rsMute) {
        proto.__rsMute = true;
        proto.play = function () {
          mute(this);
          try { this.pause(); } catch (error) {}
          return Promise.resolve();
        };
      }
      window.__repostSweepSilence = function () {
        scan(document);
      };
      function arm() {
        scan(document);
        if (!window.MutationObserver || !document.documentElement) return;
        var observer = new MutationObserver(function (records) {
          for (var i = 0; i < records.length; i += 1) {
            var added = records[i].addedNodes;
            for (var j = 0; j < added.length; j += 1) {
              var node = added[j];
              if (!node || node.nodeType !== 1) continue;
              var tag = (node.tagName || "").toLowerCase();
              if (tag === "video" || tag === "audio") mute(node);
              scan(node);
            }
          }
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });
      }
      if (document.documentElement) arm();
      else document.addEventListener("DOMContentLoaded", arm);
    })();
    """

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

private enum HandoffRewriter {
    static let callback = "repostsweep://auth-callback"
    static let universalCallback = "https://repostsweep.app/auth-callback"
    private static let httpsReturnKeys: Set<String> = [
        "redirect_uri", "return_url", "returnurl", "next", "next_url",
        "callback_url", "fallback_url", "web_url", "success_url"
    ]
    private static let redirectKeys: Set<String> = [
        "redirect_url", "redirect_uri", "redirect", "return_url", "returnurl",
        "return_to", "next", "next_url", "callback", "callback_url", "fallback_url",
        "web_url", "jump_url", "jump", "target_url",
        "target", "landing_url", "landing", "continue", "continue_url", "dest",
        "destination", "open_url", "deeplink", "deep_link", "back_url",
        "success_url", "cancel_url"
    ]
    private static let originKeys: Set<String> = [
        "from", "enter_from", "enterfrom", "source", "client", "open_from",
        "referer", "referrer", "caller", "platform", "app_type"
    ]
    private static let webOrigins: Set<String> = [
        "web", "h5", "browser", "safari", "wap", "www", "desktop", "pc", "tiktokweb"
    ]
    private static let containerKeys: Set<String> = [
        "params_url", "schema", "params", "data", "payload", "state"
    ]

    static func rewrite(_ url: URL) -> (url: URL, report: String) {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return (url, "Handoff URL could not be parsed.\n\(url.absoluteString)")
        }
        var items = components.queryItems ?? []
        var lines: [String] = []
        lines.append("Handoff URL:")
        lines.append(url.absoluteString)
        lines.append("Parameters:")
        if items.isEmpty {
            lines.append("(no query parameters)")
        }
        var replaced: [String] = []
        var origins: [String] = []
        var nested: [String] = []
        for index in items.indices {
            let name = items[index].name
            let raw = items[index].value ?? ""
            let outcome = rewriteValue(raw, key: name, depth: 0)
            let shown = raw.isEmpty ? "(empty)" : raw
            if outcome.value != raw {
                lines.append("- \(name) = \(shown)")
                lines.append("  tried: \(outcome.note)")
                items[index].value = outcome.value
                if outcome.kind == .redirect {
                    replaced.append(name)
                } else if outcome.kind == .origin {
                    origins.append("\(name)=\(fullyDecoded(raw))")
                } else if outcome.kind == .nested {
                    nested.append(name)
                }
            } else {
                lines.append("- \(name) = \(shown)")
                lines.append("  left unchanged")
            }
        }
        if replaced.isEmpty {
            let additions = [
                ("redirect_url", callback),
                ("redirect_uri", universalCallback),
                ("next", universalCallback),
                ("callback", callback)
            ]
            let existing = Set(items.map { $0.name.lowercased() })
            var added: [String] = []
            for (name, value) in additions where existing.contains(name) == false {
                items.append(URLQueryItem(name: name, value: value))
                added.append("\(name)=\(value)")
            }
            if added.isEmpty == false {
                lines.append("Tried: no redirect field was replaced, so added \(added.joined(separator: ", ")).")
            }
        } else {
            lines.append("Tried: replaced \(replaced.joined(separator: ", ")) with \(callback) or \(universalCallback).")
        }
        if origins.isEmpty == false {
            lines.append("Tried: return-target params \(origins.joined(separator: ", ")) set to repostsweep.")
        }
        if nested.isEmpty == false {
            lines.append("Tried: rewrote nested redirect fields inside \(nested.joined(separator: ", ")).")
        }
        components.queryItems = items.isEmpty ? nil : items
        let rebuilt = components.url ?? url
        lines.append("Rewritten URL:")
        lines.append(rebuilt.absoluteString)
        return (rebuilt, lines.joined(separator: "\n"))
    }

    private enum Kind {
        case unchanged
        case redirect
        case origin
        case nested
    }

    private struct Outcome {
        var value: String
        var note: String
        var kind: Kind
    }

    private static func rewriteValue(_ raw: String, key: String, depth: Int) -> Outcome {
        if depth > 6 {
            return Outcome(value: raw, note: "left unchanged", kind: .unchanged)
        }
        let decoded = fullyDecoded(raw)
        let keyName = key.lowercased()

        if let data = decoded.data(using: .utf8),
           decoded.first == "{" || decoded.first == "[",
           let object = try? JSONSerialization.jsonObject(with: data),
           object is [String: Any] || object is [Any] {
            let (rewritten, notes) = rewriteJSON(object, depth: depth + 1)
            if notes.isEmpty == false,
               let data = try? JSONSerialization.data(withJSONObject: rewritten, options: [.withoutEscapingSlashes]),
               let text = String(data: data, encoding: .utf8) {
                return Outcome(value: text, note: "nested JSON: \(notes.joined(separator: ", "))", kind: .nested)
            }
        }

        if containerKeys.contains(keyName) {
            if let nestedURL = nestedURLRewrite(decoded, depth: depth),
               nestedURL.value != decoded && nestedURL.value != raw {
                return Outcome(value: nestedURL.value, note: nestedURL.note, kind: .nested)
            }
            return Outcome(value: raw, note: "left unchanged", kind: .unchanged)
        }

        if isRedirectKey(keyName), isWebTarget(decoded) {
            let target = replacement(for: keyName)
            return Outcome(value: target, note: "replaced web return value with \(target)", kind: .redirect)
        }

        if let nestedURL = nestedURLRewrite(decoded, depth: depth) {
            if isRedirectKey(keyName), isWebTarget(nestedURL.value) || isWebTarget(decoded) {
                let target = replacement(for: keyName)
                return Outcome(value: target, note: "replaced \(key) URL with \(target). Inner: \(nestedURL.note)", kind: .redirect)
            }
            if nestedURL.value != decoded && nestedURL.value != raw {
                return Outcome(value: nestedURL.value, note: nestedURL.note, kind: .nested)
            }
        }

        if isOriginKey(keyName), isWebOrigin(decoded) {
            return Outcome(value: "repostsweep", note: "return-target \(key)=\(decoded) set to repostsweep", kind: .origin)
        }

        return Outcome(value: raw, note: "left unchanged", kind: .unchanged)
    }

    private static func nestedURLRewrite(_ decoded: String, depth: Int) -> (value: String, note: String)? {
        guard decoded.contains("://"), var components = URLComponents(string: decoded), components.queryItems?.isEmpty == false else {
            return nil
        }
        var notes: [String] = []
        var items = components.queryItems ?? []
        var changed = false
        for index in items.indices {
            let name = items[index].name
            let value = items[index].value ?? ""
            let outcome = rewriteValue(value, key: name, depth: depth + 1)
            if outcome.value != value {
                items[index].value = outcome.value
                changed = true
                notes.append("\(name): \(outcome.note)")
            }
        }
        guard changed else { return nil }
        components.queryItems = items
        let rebuilt = components.string ?? decoded
        return (rebuilt, notes.joined(separator: "; "))
    }

    private static func rewriteJSON(_ object: Any, depth: Int) -> (Any, [String]) {
        if let dict = object as? [String: Any] {
            var copy = dict
            var notes: [String] = []
            for (key, value) in dict {
                if let string = value as? String {
                    let outcome = rewriteValue(string, key: key, depth: depth)
                    if outcome.value != string {
                        copy[key] = outcome.value
                        notes.append("\(key) \(outcome.note)")
                    }
                } else if value is [String: Any] || value is [Any] {
                    let (next, inner) = rewriteJSON(value, depth: depth + 1)
                    if inner.isEmpty == false {
                        copy[key] = next
                        notes.append(contentsOf: inner)
                    }
                }
            }
            return (copy, notes)
        }
        if let array = object as? [Any] {
            var copy = array
            var notes: [String] = []
            for (index, value) in array.enumerated() {
                if let string = value as? String {
                    let outcome = rewriteValue(string, key: "[\(index)]", depth: depth)
                    if outcome.value != string {
                        copy[index] = outcome.value
                        notes.append(outcome.note)
                    }
                } else if value is [String: Any] || value is [Any] {
                    let (next, inner) = rewriteJSON(value, depth: depth + 1)
                    if inner.isEmpty == false {
                        copy[index] = next
                        notes.append(contentsOf: inner)
                    }
                }
            }
            return (copy, notes)
        }
        return (object, [])
    }

    private static func replacement(for key: String) -> String {
        httpsReturnKeys.contains(key) ? universalCallback : callback
    }

    private static func isRedirectKey(_ key: String) -> Bool {
        if redirectKeys.contains(key) { return true }
        if key.contains("redirect") || key.contains("callback") || key.contains("return") { return true }
        return false
    }

    private static func isOriginKey(_ key: String) -> Bool {
        originKeys.contains(key)
    }

    private static func isWebTarget(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return true }
        if lower.contains("tiktok.com") && (lower.contains("://") || lower.hasPrefix("www.")) { return true }
        return false
    }

    private static func isWebOrigin(_ value: String) -> Bool {
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if webOrigins.contains(lower) { return true }
        if lower.contains("tiktok.com") { return true }
        return false
    }

    private static func fullyDecoded(_ value: String) -> String {
        var current = value
        for _ in 0..<4 {
            guard let next = current.removingPercentEncoding, next != current else { break }
            current = next
        }
        return current
    }
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
            self.silencePlayback(on: self.webView)
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
