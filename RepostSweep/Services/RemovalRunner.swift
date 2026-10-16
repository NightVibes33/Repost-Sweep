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
    @Published private(set) var statusText = "Getting ready"
    @Published private(set) var siteChangeDetail: String?

    private var stopRequested = false
    private var startedAt: Date?
    private let spacingRange: ClosedRange<TimeInterval> = 2.2...3.4
    private let rateLimitBackoff: TimeInterval = 25

    var processed: Int {
        completed + failed
    }

    var remainingCount: Int {
        max(0, total - processed)
    }

    var estimateText: String {
        guard isFinished == false else { return "Finished" }
        if isPaused { return "Paused" }
        let left = remainingCount
        guard left > 0, isRunning else { return statusText }
        let pace: TimeInterval
        if completed >= 1, let startedAt {
            pace = max(2.2, Date().timeIntervalSince(startedAt) / Double(max(completed, 1)))
        } else {
            pace = 2.8
        }
        let seconds = Int(pace * Double(left))
        if seconds < 50 {
            return "Under a minute left"
        }
        let minutes = Int((Double(seconds) / 60).rounded(.up))
        return "About \(minutes) min left"
    }

    func togglePause() {
        guard isRunning, isFinished == false else { return }
        isPaused.toggle()
        statusText = isPaused ? "Paused. Nothing else will be removed until you resume." : "Resuming."
    }

    func stop() {
        stopRequested = true
        isPaused = false
        statusText = "Stopping after the current repost."
    }

    func start(
        items: [RepostItem],
        session: TikTokWebSession,
        freeTier: FreeTierStore,
        purchases: PurchaseManager
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
        startedAt = Date()
        statusText = "Starting"
        isRunning = true
        session.removalActive = true

        Task {
            await run(items: items, session: session, freeTier: freeTier, purchases: purchases)
        }
    }

    private func run(
        items: [RepostItem],
        session: TikTokWebSession,
        freeTier: FreeTierStore,
        purchases: PurchaseManager
    ) async {
        var streak = 0
        for item in items {
            if stopRequested { break }
            await waitWhilePaused()
            if stopRequested { break }

            let subscribed = purchases.isSubscribed
            if subscribed == false, freeTier.remaining <= 0 {
                needsPaywall = true
                statusText = "The free removals on this device are used up."
                break
            }

            current = item
            statusText = "Removing \(completed + failed + 1) of \(total)"
            let outcome = await removeWithRetry(item: item, session: session)
            switch outcome {
            case .removed:
                completed += 1
                streak = 0
                if subscribed == false {
                    freeTier.recordRemoval()
                }
                session.reposts.removeAll { $0.id == item.id }
                if item.id != items.last?.id && stopRequested == false {
                    await sleep(spacingRange)
                }
            case .rateLimited:
                failed += 1
                streak += 1
                statusText = "TikTok asked for a longer pause."
                await sleep(rateLimitBackoff...rateLimitBackoff)
            case .notLoggedIn:
                statusText = "TikTok signed this session out. Sign in again, then retry the rest."
                stopRequested = true
            case .siteChanged(let detail):
                siteChangeDetail = detail
                session.siteChangeMessage = detail
                statusText = "Stopped because TikTok’s page changed."
                stopRequested = true
            case .failed:
                failed += 1
                streak += 1
                if streak >= 3 {
                    statusText = "Three removals failed in a row, so the sweep stopped. The ones that succeeded are already gone."
                    stopRequested = true
                } else {
                    await sleep(spacingRange)
                }
            }
        }

        current = nil
        session.removalActive = false
        isRunning = false
        isFinished = true
        isPaused = false
        let canSummarize = statusText.hasPrefix("Removing") || statusText == "Starting" || statusText.hasPrefix("Resuming")
        if siteChangeDetail == nil, needsPaywall == false, canSummarize {
            statusText = "Removed \(completed). \(failed) didn’t go through."
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
