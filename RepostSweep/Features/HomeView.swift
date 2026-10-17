import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var session: TikTokWebSession
    @EnvironmentObject private var purchases: PurchaseManager
    @EnvironmentObject private var freeTier: FreeTierStore
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var runner: RemovalRunner

    @State private var selected: Set<String> = []
    @State private var pendingItems: [RepostItem] = []
    @State private var cappedItems: [RepostItem] = []
    @State private var confirmRemove = false
    @State private var confirmStop = false
    @State private var showPartial = false
    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var confirmSignOut = false
    @State private var showingSuccess = false
    @State private var selectMode = false

    private var hasAccount: Bool {
        session.account?.uniqueId.isEmpty == false
    }

    private var selectedItems: [RepostItem] {
        session.reposts.filter { selected.contains($0.id) }
    }

    private var awaitingFirstScan: Bool {
        hasAccount && session.didScan == false && runner.isRunning == false
    }

    private var showCaughtUp: Bool {
        hasAccount && session.didScan && session.isWorking == false && runner.isRunning == false && session.reposts.isEmpty && session.notice == nil
    }

    private var primaryTitle: String {
        if selectMode, selectedItems.isEmpty == false, selectedItems.count < session.reposts.count {
            return selectedItems.count == 1 ? "Remove 1 repost" : "Remove \(selectedItems.count) reposts"
        }
        return "Remove All Reposts"
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.showLoginSuccess {
                    loginSuccess
                } else if hasAccount == false && (session.isWorking || (session.hasSessionCookie && session.didScan == false && session.notice == nil)) {
                    profileLoading
                } else if hasAccount == false {
                    signIn
                } else if runner.isRunning {
                    progress
                } else if showingSuccess {
                    success
                } else {
                    dashboard
                }
            }
            .animation(Motion.spring, value: session.showLoginSuccess)
            .animation(Motion.spring, value: hasAccount)
            .animation(Motion.spring, value: runner.isRunning)
            .animation(Motion.spring, value: showingSuccess)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationDestination(isPresented: $showHistory) {
                HistoryView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .sweepSheetChrome()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .sweepSheetChrome()
            }
            .confirmationDialog(
                "Remove \(pendingItems.count) \(pendingItems.count == 1 ? "repost" : "reposts")?",
                isPresented: $confirmRemove,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    begin(pendingItems)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They leave your reposts tab. Original videos stay up. Each one waits a couple of seconds.")
            }
            .confirmationDialog(
                "The free tier covers \(freeTier.remaining) more",
                isPresented: $showPartial,
                titleVisibility: .visible
            ) {
                Button("Remove \(freeTier.remaining) free") {
                    pendingItems = cappedItems
                    confirmRemove = true
                }
                Button("See plans") {
                    showPaywall = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A subscription removes the cap.")
            }
            .confirmationDialog("Log out of TikTok in this app?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Log out", role: .destructive) {
                    selected.removeAll()
                    selectMode = false
                    showHistory = false
                    showingSuccess = false
                    Task { await session.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears the in-app browser. Your password was never stored.")
            }
            .confirmationDialog("Stop removing?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Stop", role: .destructive) {
                    runner.stop()
                }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("Reposts already removed stay off your tab.")
            }
            .onChange(of: runner.needsPaywall) { needs in
                if needs {
                    showPaywall = true
                }
            }
            .onChange(of: runner.isRunning) { running in
                if running {
                    showingSuccess = false
                    selectMode = false
                }
            }
            .onChange(of: runner.isFinished) { finished in
                guard finished, runner.isRunning == false else { return }
                if session.reposts.isEmpty, session.notice == nil, runner.completed > 0 {
                    showingSuccess = true
                }
            }
            .task(id: session.showLoginSuccess) {
                guard session.showLoginSuccess else { return }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                session.showLoginSuccess = false
            }
        }
    }

    private var loginSuccess: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: ScreenLayout.isNarrow ? 64 : 80, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.success)
                .accessibilityHidden(true)
            Text("You’re in")
                .font(Typeface.largeTitle)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            Text("Opening your reposts.")
                .font(Typeface.body)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, ScreenLayout.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScreenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var profileLoading: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .tint(Theme.ink)
            Text("Opening your profile")
                .font(Typeface.title)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text("This stays inside the app.")
                .font(Typeface.body)
                .foregroundStyle(Theme.muted)
            Spacer()
        }
        .padding(.horizontal, ScreenLayout.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var signIn: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: 24) {
                    if let notice = session.notice {
                        noticeCard(notice)
                    }
                    AppGlyph(size: ScreenLayout.isNarrow ? 96 : 112)
                        .padding(.top, 28)
                    Text("Sweep your\nreposts.")
                        .font(Typeface.largeTitle)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(LegalCopy.password)
                        .font(Typeface.body)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    LaurelLine(title: "Originals stay up", detail: "Only your repost tab changes")
                }
                .padding(.horizontal, ScreenLayout.horizontal)
                .readableColumn()
            }
            VStack(spacing: 12) {
                loginControl
                Text(LegalCopy.notAffiliated)
                    .font(Typeface.caption)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, ScreenLayout.horizontal)
            .padding(.bottom, 16)
            .readableColumn()
        }
        .background(ScreenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let notice = session.notice {
                        noticeCard(notice)
                    }
                    accountCard
                    countBlock
                    #if !SIDELOAD_UNLOCK
                    if purchases.isSubscribed == false {
                        FreeMeter(
                            used: freeTier.used,
                            limit: Monetization.freeRemovalLimit,
                            subscribed: purchases.isSubscribed
                        ) {
                            showPaywall = true
                        }
                    }
                    #endif
                    if let banner = session.banner, banner.isEmpty == false {
                        Text(banner)
                            .font(Typeface.secondary)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    repostGrid
                    #if DEBUG_UI
                    if session.debugDetail.isEmpty == false {
                        debugDetail
                    }
                    #endif
                    Text(LegalCopy.removals)
                        .font(Typeface.caption)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, ScreenLayout.horizontal)
                .padding(.bottom, 12)
                .readableColumn()
            }
            .refreshable {
                await session.loadReposts()
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar {
                if session.isWorking || awaitingFirstScan {
                    PrimaryButton(title: "Looking for reposts", systemImage: "hourglass", enabled: false) {}
                } else if session.reposts.isEmpty {
                    PrimaryButton(title: "Scan again", systemImage: "arrow.clockwise") {
                        Task { await session.loadReposts() }
                    }
                } else {
                    PrimaryButton(title: primaryTitle, systemImage: "trash") {
                        let subset = selectMode && selectedItems.isEmpty == false && selectedItems.count < session.reposts.count
                        prepare(all: subset == false)
                    }
                }
            }
        }
    }

    private var progress: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                topBar
                VStack(spacing: 20) {
                    Spacer(minLength: 8)
                    MetricRing(progress: ringProgress) {
                        VStack(spacing: 2) {
                            Text("\(runner.completed)")
                                .font(.system(size: ScreenLayout.isNarrow ? 44 : 56, weight: .bold))
                                .foregroundStyle(Theme.ink)
                                .monospacedDigit()
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                                .numericTextTransition()
                            Text("of \(runner.total)")
                                .font(Typeface.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(
                        width: ScreenLayout.progressRing(width: geo.size.width, height: geo.size.height),
                        height: ScreenLayout.progressRing(width: geo.size.width, height: geo.size.height)
                    )
                    .accessibilityLabel("\(runner.completed) of \(runner.total) removed")
                    Text(runner.statusText.isEmpty ? "Removing" : runner.statusText)
                        .font(Typeface.body)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    if let title = runner.current?.titleLine, title.isEmpty == false {
                        Text(title)
                            .font(Typeface.secondary)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, ScreenLayout.horizontal)
                .readableColumn()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(ScreenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar {
                HStack(spacing: 8) {
                    QuietButton(title: runner.isPaused ? "Resume" : "Pause", systemImage: runner.isPaused ? "play.fill" : "pause.fill") {
                        runner.togglePause()
                    }
                    QuietButton(title: "Stop", systemImage: "stop.fill") {
                        confirmStop = true
                    }
                }
            }
        }
    }

    private var success: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: ScreenLayout.isNarrow ? 64 : 80, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.success)
                    .accessibilityHidden(true)
                Text("All caught up")
                    .font(Typeface.largeTitle)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text(runner.completed == 1 ? "1 repost left your tab." : "\(runner.completed) reposts left your tab.")
                    .font(Typeface.body)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, ScreenLayout.horizontal)
            .readableColumn()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScreenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar {
                PrimaryButton(title: "Done") {
                    showingSuccess = false
                }
            }
        }
    }

    private var ringProgress: Double? {
        guard runner.total > 0 else { return nil }
        return Double(runner.processed) / Double(runner.total)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            MarkView(size: 28)
            Text("Repost Sweep")
                .font(Typeface.title)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            IconChip(systemName: "gearshape") {
                showSettings = true
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, ScreenLayout.horizontal)
        .padding(.top, 8)
        .readableColumn()
    }

    private var countBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showCaughtUp {
                Text("All caught up")
                    .font(Typeface.largeTitle)
                    .foregroundStyle(Theme.ink)
                Text("Nothing left on the repost tab.")
                    .font(Typeface.body)
                    .foregroundStyle(Theme.muted)
            } else if awaitingFirstScan || (session.isWorking && session.reposts.isEmpty) {
                Text("…")
                    .font(.system(size: ScreenLayout.isNarrow ? 48 : 56, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(session.statusText.isEmpty ? "Looking for reposts" : session.statusText)
                    .font(Typeface.body)
                    .foregroundStyle(Theme.muted)
            } else {
                Text("\(session.reposts.count)")
                    .font(.system(size: ScreenLayout.isNarrow ? 48 : 56, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                    .numericTextTransition()
                    .accessibilityLabel("\(session.reposts.count) reposts")
                Text(session.reposts.count == 1 ? "repost" : "reposts")
                    .font(Typeface.body)
                    .foregroundStyle(Theme.muted)
            }
            Button {
                showHistory = true
            } label: {
                Text("\(history.lifetimeRemoved) removed")
                    .font(Typeface.caption)
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityLabel("\(history.lifetimeRemoved) removed. Open history.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountCard: some View {
        SurfaceCard {
            HStack(spacing: 12) {
                AvatarView(
                    urlString: session.account?.avatarURL ?? "",
                    fallback: session.account?.nickname.isEmpty == false
                        ? (session.account?.nickname ?? "")
                        : (session.account?.uniqueId ?? "T"),
                    size: 52
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(accountTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(accountSubtitle)
                        .font(Typeface.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    if let stats = session.account?.statsLine {
                        Text(stats)
                            .font(Typeface.caption)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Button("Log out") {
                    Haptics.tap()
                    confirmSignOut = true
                }
                .font(Typeface.caption)
                .foregroundStyle(Theme.ink)
            }
        }
    }

    private var accountTitle: String {
        if let account = session.account, account.nickname.isEmpty == false {
            return account.nickname
        }
        if let account = session.account, account.uniqueId.isEmpty == false {
            return "@\(account.uniqueId)"
        }
        return "TikTok"
    }

    private var accountSubtitle: String {
        if let account = session.account, account.uniqueId.isEmpty == false, account.nickname.isEmpty == false {
            return "@\(account.uniqueId)"
        }
        return "TikTok"
    }

    @ViewBuilder
    private var repostGrid: some View {
        if session.isWorking || awaitingFirstScan {
            VStack(spacing: 8) {
                SkeletonRow()
                SkeletonRow()
            }
        } else if session.reposts.isEmpty == false {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Reposts")
                        .font(Typeface.title)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Button(selectMode ? "Done" : "Select") {
                        Haptics.select()
                        selectMode.toggle()
                        if selectMode == false {
                            selected.removeAll()
                        }
                    }
                    .font(Typeface.secondary)
                    .foregroundStyle(Theme.ink)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(session.reposts) { item in
                        RepostTile(
                            item: item,
                            image: session.thumbnails[item.id],
                            selected: selected.contains(item.id),
                            selecting: selectMode
                        ) {
                            if selectMode {
                                toggle(item.id)
                            } else {
                                selectMode = true
                                selected = [item.id]
                            }
                        }
                        .task(id: item.id) {
                            await session.loadThumbnail(for: item)
                        }
                    }
                }
            }
        }
    }

    #if DEBUG_UI
    private var debugDetail: some View {
        SurfaceCard {
            DisclosureGroup {
                Text(session.debugDetail)
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
    #endif

    private func noticeCard(_ notice: SweepNotice) -> some View {
        SweepErrorCard(notice: notice) {
            Task { await session.loadReposts() }
        } onViewPage: {
            session.openDebugPage()
        } onLogin: {
            session.beginLogin()
        }
    }

    private var loginControl: some View {
        TikTokLoginControl(phase: session.appLoginPhase, finishing: session.isFinishingReturn) {
            session.beginLogin()
        } onCancel: {
            session.cancelLogin()
        }
    }

    private func toggle(_ id: String) {
        guard runner.isRunning == false else { return }
        Haptics.select()
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func prepare(all: Bool) {
        let chosen = all ? session.reposts : selectedItems
        guard chosen.isEmpty == false else { return }
        if purchases.isSubscribed || chosen.count <= freeTier.remaining {
            pendingItems = chosen
            confirmRemove = true
            return
        }
        if freeTier.remaining == 0 {
            showPaywall = true
            return
        }
        cappedItems = Array(chosen.prefix(freeTier.remaining))
        showPartial = true
    }

    private func begin(_ items: [RepostItem]) {
        guard items.isEmpty == false, runner.isRunning == false else { return }
        runner.start(
            items: items,
            session: session,
            freeTier: freeTier,
            purchases: purchases,
            history: history
        )
    }
}
