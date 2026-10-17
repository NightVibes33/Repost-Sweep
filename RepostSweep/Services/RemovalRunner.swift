import Combine
import Foundation

@MainActor
final class RemovalRunner: ObservableObject {
    @Published private(set) var total = 0
    @Published private(set) var completed = 0
    @Published private(set) var failed = 0
    @Published private(set) var current: RepostItem?
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var isFinished = false
    @Published private(set) var needsPaywall = false
    @Published private(set) var statusText = ""
    @Published private(set) var siteChangeDetail: String?

    private var stopRequested = false
    private let spacingRange: ClosedRange<TimeInterval> = 2.2...3.4
    private let rateLimitBackoff: TimeInterval = 25

    var processed: Int {
        completed + failed
    }

    var remainingCount: Int {
        max(0, total - processed)
    }

    func togglePause() {
        guard isRunning, isFinished == false else { return }
        isPaused.toggle()
        statusText = isPaused ? "Paused" : "Resuming"
    }

    func stop() {
        stopRequested = true
        isPaused = false
        statusText = "Stopping"
    }

    func start(
        items: [RepostItem],
        session: TikTokWebSession,
        freeTier: FreeTierStore,
        purchases: PurchaseManager,
        history: HistoryStore
    ) {
        guard isRunning == false else { return }
        total = items.count
        completed = 0
        failed = 0
        current = nil
        isPaused = false
        isFinished = false
        needsPaywall = false
        siteChangeDetail = nil
        stopRequested = false
        statusText = "Starting"
        session.debugDetail = ""
        isRunning = true
        session.removalActive = true
        Haptics.burst()

        Task {
            await run(items: items, session: session, freeTier: freeTier, purchases: purchases, history: history)
        }
    }

    private func run(
        items: [RepostItem],
        session: TikTokWebSession,
        freeTier: FreeTierStore,
        purchases: PurchaseManager,
        history: HistoryStore
    ) async {
        var streak = 0
        for item in items {
            if stopRequested { break }
            await waitWhilePaused()
            if stopRequested { break }

            if purchases.isSubscribed == false, freeTier.remaining <= 0 {
                needsPaywall = true
                statusText = "Free removals are used up"
                break
            }

            current = item
            statusText = "Removing \(completed + failed + 1) of \(total)"
            let outcome = await removeWithRetry(item: item, session: session)
            switch outcome {
            case .removed:
                completed += 1
                streak = 0
                if purchases.isSubscribed == false {
                    freeTier.recordRemoval()
                }
                history.record(item: item, removed: true, detail: "")
                session.reposts.removeAll { $0.id == item.id }
                if item.id != items.last?.id && stopRequested == false {
                    await sleep(spacingRange)
                }
            case .rateLimited:
                failed += 1
                streak += 1
                history.record(item: item, removed: false, detail: "TikTok asked for a pause")
                statusText = "TikTok asked for a pause"
                await sleep(rateLimitBackoff...rateLimitBackoff)
            case .notLoggedIn:
                session.notice = SweepNotice(
                    title: "TikTok signed you out",
                    message: "The session expired before this repost could be removed. Log in again, then retry the rest. Original videos were not deleted.",
                    debugHint: "NOT_LOGGED_IN",
                    suggestLogin: true
                )
                statusText = "Signed out"
                stopRequested = true
            case .siteChanged(let detail):
                siteChangeDetail = detail
                session.siteChangeMessage = detail
                session.notice = SweepNotice(
                    title: "TikTok changed this step",
                    message: "Removal stopped so nothing else was guessed. Reposts that already went through are done. Original videos were not deleted.",
                    debugHint: detail
                )
                history.record(item: item, removed: false, detail: "Page changed")
                statusText = "Stopped"
                stopRequested = true
            case .failed(let detail):
                failed += 1
                streak += 1
                history.record(item: item, removed: false, detail: detail.isEmpty ? "Didn’t go through" : detail)
                if streak >= 3 {
                    session.notice = SweepNotice(
                        title: "Removal paused after three misses",
                        message: "Three reposts in a row didn’t go through, so the sweep stopped. The ones that succeeded are already off your reposts tab.",
                        debugHint: detail
                    )
                    statusText = "Stopped"
                    stopRequested = true
                } else {
                    await sleep(spacingRange)
                }
            }
        }

        current = nil
        session.removalActive = false
        session.parkWebView()
        isRunning = false
        isFinished = true
        isPaused = false
        if siteChangeDetail == nil, needsPaywall == false, session.notice == nil {
            if completed > 0 && failed == 0 {
                session.banner = "Removed \(completed) from your repost tab."
                statusText = "Removed \(completed)"
            } else if completed > 0 {
                session.banner = "Removed \(completed). \(failed) stayed on the tab."
                statusText = "Removed \(completed)"
            } else if stopRequested {
                statusText = "Stopped"
            } else {
                statusText = ""
            }
        }
        if completed > 0 && siteChangeDetail == nil {
            Haptics.success()
        } else if failed > 0 || siteChangeDetail != nil {
            Haptics.warning()
        }
    }

    private func removeWithRetry(item: RepostItem, session: TikTokWebSession) async -> RemovalAttempt {
        let first = await session.remove(itemId: item.id)
        switch first {
        case .rateLimited, .failed:
            await sleep(rateLimitBackoff...rateLimitBackoff)
            if stopRequested { return first }
            return await session.remove(itemId: item.id)
        default:
            return first
        }
    }

    private func waitWhilePaused() async {
        while isPaused && stopRequested == false {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func sleep(_ range: ClosedRange<TimeInterval>) async {
        var remaining = Double.random(in: range)
        while remaining > 0 && stopRequested == false {
            await waitWhilePaused()
            if stopRequested { return }
            let slice = min(0.25, remaining)
            try? await Task.sleep(nanoseconds: UInt64(slice * 1_000_000_000))
            remaining -= slice
        }
    }
}
