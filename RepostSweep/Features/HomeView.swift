import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var session: TikTokWebSession
    @EnvironmentObject private var purchases: PurchaseManager
    @EnvironmentObject private var freeTier: FreeTierStore
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var runner: RemovalRunner

    @Namespace private var selectionBar

    @State private var selected: Set<String> = []
    @State private var pendingItems: [RepostItem] = []
    @State private var cappedItems: [RepostItem] = []
    @State private var confirmRemove = false
    @State private var confirmStop = false
    @State private var showPartial = false
    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showList = false
    @State private var confirmSignOut = false
    @State private var showingSuccess = false

    private var signedIn: Bool {
        session.hasSessionCookie || (session.account?.uniqueId.isEmpty == false)
    }

    private var selectedItems: [RepostItem] {
        session.reposts.filter { selected.contains($0.id) }
    }

    private var allSelected: Bool {
        session.reposts.isEmpty == false && selectedItems.count == session.reposts.count
    }

    private var awaitingFirstScan: Bool {
        signedIn && session.didScan == false && runner.isRunning == false
    }

    private var showCaughtUp: Bool {
        signedIn && session.didScan && session.isWorking == false && runner.isRunning == false && session.reposts.isEmpty && session.notice == nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.showLoginSuccess {
                    loginSuccess
                } else if signedIn == false {
                    signIn
                } else if runner.isRunning || showingSuccess {
                    progress
                } else {
                    dashboard
                }
            }
            .animation(Motion.spring, value: session.showLoginSuccess)
            .animation(Motion.spring, value: signedIn)
            .animation(Motion.spring, value: runner.isRunning)
            .animation(Motion.spring, value: showingSuccess)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationDestination(isPresented: $showHistory) {
                HistoryView()
            }
            .navigationDestination(isPresented: $showList) {
                repostList
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
                    showList = false
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
            .onChange(of: session.isWorking) { working in
                if working == false, session.reposts.isEmpty == false, runner.isRunning == false {
                    selected = Set(session.reposts.map(\.id))
                }
            }
            .onChange(of: runner.isRunning) { running in
                if running {
                    showingSuccess = false
                    showList = false
                }
            }
            .onChange(of: runner.isFinished) { finished in
                guard finished, runner.isRunning == false else { return }
                if session.reposts.isEmpty, session.notice == nil, runner.completed > 0 {
                    showingSuccess = true
                }
            }
            .onAppear {
                if selected.isEmpty, session.reposts.isEmpty == false {
                    selected = Set(session.reposts.map(\.id))
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
                .font(.system(size: ScreenLayout.isNarrow ? 72 : 84, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.success)
                .accessibilityHidden(true)
            Text("You’re in")
                .font(Typeface.largeTitle)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            Text("TikTok sent you back. Opening your reposts.")
                .font(Typeface.body)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, Theme.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScreenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var signIn: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, Theme.margin)
                .readableColumn()
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 36)
                    if let notice = session.notice {
                        SweepErrorCard(notice: notice) {
                            Task { await session.loadReposts() }
                        } onViewPage: {
                            session.openDebugPage()
                        } onLogin: {
                            session.beginLogin()
                        }
                    }
                    AppGlyph(size: 112)
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
                        .padding(.top, 8)
                }
                .padding(.horizontal, Theme.margin)
                .readableColumn()
            }
            VStack(spacing: 12) {
                loginControl
                Text(LegalCopy.notAffiliated)
                    .font(Typeface.caption)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 16)
            .readableColumn()
        }
        .background(ScreenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, Theme.margin)
                .readableColumn()
            dashboardScroll
        }
        .background(Theme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar {
                dashboardActions
                    .matchedGeometryEffect(id: "selectionBar", in: selectionBar, isSource: showList == false)
            }
        }
    }

    private var dashboardScroll: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let notice = session.notice {
                    SweepErrorCard(notice: notice) {
                        Task { await session.loadReposts() }
                    } onViewPage: {
                        session.openDebugPage()
                    } onLogin: {
                        session.beginLogin()
                    }
                }
                accountCard
                countBlock
                FreeMeter(
                    used: freeTier.used,
                    limit: Monetization.freeRemovalLimit,
                    subscribed: purchases.isSubscribed
                ) {
                    showPaywall = true
                }
                if let banner = session.banner, banner.isEmpty == false {
                    Text(banner)
                        .font(Typeface.secondary)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(Theme.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                .strokeBorder(Theme.line, lineWidth: 1)
                        )
                }
                if session.reposts.isEmpty == false {
                    lastReposts
                } else if session.isWorking || awaitingFirstScan {
                    VStack(spacing: 8) {
                        SkeletonRow()
                        SkeletonRow()
                        SkeletonRow()
                    }
                }
                if session.debugDetail.isEmpty == false {
                    debugDetail
                }
                Text(LegalCopy.removals)
                    .font(Typeface.caption)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 12)
            .readableColumn()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .refreshable {
            await session.loadReposts()
        }
    }

    private var progress: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, Theme.margin)
                .readableColumn()
            if showingSuccess && runner.isRunning == false {
                successBody
            } else {
                runningBody
            }
        }
        .background(ScreenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar {
                if showingSuccess && runner.isRunning == false {
                    PrimaryButton(title: "Done") {
                        showingSuccess = false
                    }
                } else {
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
    }

    private var runningBody: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)
            MetricRing(progress: ringProgress) {
                VStack(spacing: 2) {
                    RollingNumber(value: Double(runner.remainingCount))
                        .frame(maxWidth: 160)
                        .animation(Motion.spring, value: runner.remainingCount)
                    Text("left")
                        .font(Typeface.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(width: ScreenLayout.ring, height: ScreenLayout.ring)
            .accessibilityLabel("\(runner.remainingCount) left")
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
            Spacer(minLength: 12)
        }
        .padding(.horizontal, Theme.margin)
        .readableColumn()
    }

    private var successBody: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 84, weight: .regular))
                .foregroundStyle(Theme.success)
                .accessibilityHidden(true)
            Text("All caught up!")
                .font(Typeface.largeTitle)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text("Those reposts are off your tab.")
                .font(Typeface.body)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, Theme.margin)
        .readableColumn()
    }

    private var ringProgress: Double? {
        guard runner.total > 0 else { return nil }
        return Double(runner.processed) / Double(runner.total)
    }

    private var repostList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(allSelected ? "All selected" : "\(selectedItems.count) selected")
                        .font(Typeface.secondary)
                        .foregroundStyle(Theme.muted)
                        .numericTextTransition()
                    Spacer()
                    Button(allSelected ? "Clear" : "Select all") {
                        Haptics.select()
                        if allSelected {
                            selected.removeAll()
                        } else {
                            selected = Set(session.reposts.map(\.id))
                        }
                    }
                    .font(Typeface.secondary)
                    .foregroundStyle(Theme.ink)
                    .disabled(runner.isRunning)
                }
                LazyVStack(spacing: 8) {
                    ForEach(session.reposts) { item in
                        RepostCard(
                            item: item,
                            image: session.thumbnails[item.id],
                            selected: selected.contains(item.id),
                            active: runner.current?.id == item.id,
                            showsSelection: true
                        ) {
                            toggle(item.id)
                        }
                        .task(id: item.id) {
                            await session.loadThumbnail(for: item)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .readableColumn()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Reposts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable {
            await session.loadReposts()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar {
                PrimaryButton(
                    title: selectedItems.isEmpty ? "Select reposts" : "Remove \(selectedItems.count)",
                    enabled: selectedItems.isEmpty == false
                ) {
                    prepare(all: false)
                }
                .matchedGeometryEffect(id: "selectionBar", in: selectionBar, isSource: showList)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            MarkView(size: 28)
            Text("Repost Sweep")
                .font(Typeface.title)
                .foregroundStyle(Theme.ink)
            Spacer()
            IconChip(systemName: "gearshape") {
                showSettings = true
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    private var countBlock: some View {
        VStack(spacing: 16) {
            if showCaughtUp {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Theme.success)
                    Text("All caught up!")
                        .font(Typeface.largeTitle)
                        .foregroundStyle(Theme.ink)
                    Text("Nothing left on the repost tab.")
                        .font(Typeface.body)
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                MetricRing(progress: session.isWorking && session.reposts.isEmpty ? nil : 1) {
                    VStack(spacing: 2) {
                        if signedIn == false {
                            Text("—")
                                .font(Typeface.hero)
                                .foregroundStyle(Theme.ink)
                        } else if awaitingFirstScan || (session.isWorking && session.reposts.isEmpty) {
                            Text("…")
                                .font(Typeface.hero)
                                .foregroundStyle(Theme.ink)
                        } else {
                            RollingNumber(value: Double(session.reposts.count))
                                .frame(maxWidth: 160)
                                .animation(Motion.spring, value: session.reposts.count)
                        }
                        Text(heroCaption)
                            .font(Typeface.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(width: ScreenLayout.ring, height: ScreenLayout.ring)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(session.reposts.count) reposts")
            }
            Button {
                showHistory = true
            } label: {
                Text("\(history.lifetimeRemoved) removed")
                    .font(Typeface.caption)
                    .foregroundStyle(Theme.muted)
                    .numericTextTransition()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(history.lifetimeRemoved) removed. Open history.")
        }
    }

    private var heroCaption: String {
        if awaitingFirstScan || session.isWorking {
            return session.statusText.isEmpty ? "Looking" : session.statusText
        }
        return session.reposts.count == 1 ? "repost" : "reposts"
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
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
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
        return "TikTok account"
    }

    private var accountSubtitle: String {
        if let account = session.account, account.uniqueId.isEmpty == false, account.nickname.isEmpty == false {
            return "@\(account.uniqueId)"
        }
        if session.account?.uniqueId.isEmpty == false {
            return "Signed in"
        }
        return "Loading profile"
    }

    private var lastReposts: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last reposts")
                    .font(Typeface.title)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("View all") {
                    withAnimation(Motion.spring) {
                        showList = true
                    }
                }
                .font(Typeface.secondary)
                .foregroundStyle(Theme.ink)
            }
            ForEach(Array(session.reposts.prefix(3))) { item in
                RepostCard(
                    item: item,
                    image: session.thumbnails[item.id],
                    selected: false,
                    active: false,
                    showsSelection: false
                ) {
                    withAnimation(Motion.spring) {
                        showList = true
                    }
                }
                .task(id: item.id) {
                    await session.loadThumbnail(for: item)
                }
            }
        }
    }

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

    @ViewBuilder
    private var dashboardActions: some View {
        if session.isWorking || awaitingFirstScan {
            PrimaryButton(title: "Looking for reposts", systemImage: "hourglass", enabled: false) {}
        } else if session.reposts.isEmpty {
            PrimaryButton(title: "Scan again", systemImage: "arrow.clockwise") {
                Task { await session.loadReposts() }
            }
        } else {
            QuietButton(title: "Refresh", systemImage: "arrow.clockwise") {
                Task { await session.loadReposts() }
            }
            PrimaryButton(title: "Remove all", systemImage: "trash") {
                prepare(all: true)
            }
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
        withAnimation(Motion.spring) {
            if selected.contains(id) {
                selected.remove(id)
            } else {
                selected.insert(id)
            }
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
