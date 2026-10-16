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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    if signedIn {
                        accountCard
                        FreeMeter(
                            used: freeTier.used,
                            limit: Monetization.freeRemovalLimit,
                            subscribed: purchases.isSubscribed
                        ) {
                            showPaywall = true
                        }
                    } else {
                        signedOutCard
                    }
                    if let banner = session.banner, banner.isEmpty == false {
                        Text(banner)
                            .font(.footnote)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    if let notice = session.notice {
                        SweepErrorCard(notice: notice) {
                            Task { await session.loadReposts() }
                        } onViewPage: {
                            session.openDebugPage()
                        } onLogin: {
                            session.beginLogin()
                        }
                    }
                    if session.reposts.isEmpty == false {
                        listHeader
                        LazyVStack(spacing: 8) {
                            ForEach(session.reposts) { item in
                                RepostRow(
                                    item: item,
                                    image: session.thumbnails[item.id],
                                    selected: selected.contains(item.id),
                                    active: runner.current?.id == item.id
                                ) {
                                    toggle(item.id)
                                }
                                .task(id: item.id) {
                                    await session.loadThumbnail(for: item)
                                }
                            }
                        }
                    } else if session.isWorking || awaitingFirstScan {
                        loadingRows
                    } else if showCaughtUp {
                        caughtUp
                    }
                    Text(LegalCopy.removals)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .readableColumn()
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 8) {
                        MarkView(size: 26)
                        Text("Repost Sweep")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
            .refreshable {
                await session.loadReposts()
            }
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
            .onAppear {
                if selected.isEmpty, session.reposts.isEmpty == false {
                    selected = Set(session.reposts.map(\.id))
                }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 8) {
            ZStack {
                if runner.isRunning {
                    ProgressRing(progress: runner.total == 0 ? 0 : Double(runner.processed) / Double(max(runner.total, 1)))
                        .frame(width: 168, height: 168)
                }
                VStack(spacing: 2) {
                    Text(heroValue)
                        .font(.system(size: runner.isRunning ? 52 : 72, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(heroCaption)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(showCaughtUp ? Theme.success : Theme.muted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            if runner.current != nil {
                Text(runner.current?.titleLine ?? "")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }

            Button {
                showHistory = true
            } label: {
                Text("\(history.lifetimeRemoved) removed")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.surface)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(history.lifetimeRemoved) removed. Open history.")
        }
    }

    private var heroValue: String {
        if signedIn == false {
            return "—"
        }
        if runner.isRunning {
            return "\(runner.remainingCount)"
        }
        if awaitingFirstScan || (session.isWorking && session.reposts.isEmpty) {
            return "…"
        }
        return "\(session.reposts.count)"
    }

    private var heroCaption: String {
        if signedIn == false {
            return "Not signed in"
        }
        if runner.isRunning || runner.isPaused {
            return runner.statusText.isEmpty ? "Removing" : runner.statusText
        }
        if awaitingFirstScan || session.isWorking {
            return session.statusText.isEmpty ? "Looking for reposts" : session.statusText
        }
        if showCaughtUp {
            return "All caught up"
        }
        return "reposts left"
    }

    private var accountCard: some View {
        SurfaceCard {
            HStack(spacing: 12) {
                AvatarView(
                    urlString: session.account?.avatarURL ?? "",
                    fallback: session.account?.nickname.isEmpty == false
                        ? (session.account?.nickname ?? "")
                        : (session.account?.uniqueId ?? "T"),
                    size: 46
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(accountTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(accountSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("Log out") {
                    Haptics.tap()
                    confirmSignOut = true
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.pink)
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

    private var signedOutCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Log in on TikTok’s page")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(LegalCopy.password)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var listHeader: some View {
        HStack {
            Text("Reposts")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button {
                Haptics.select()
                if allSelected {
                    selected.removeAll()
                } else {
                    selected = Set(session.reposts.map(\.id))
                }
            } label: {
                Text(selectedItems.isEmpty ? "Select all" : "\(selectedItems.count) selected")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.pink)
            }
            .disabled(runner.isRunning)
        }
        .padding(.top, 4)
    }

    private var loadingRows: some View {
        VStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.surface)
                    .frame(height: 74)
            }
        }
    }

    private var caughtUp: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.success)
            Text("Nothing left on the repost tab.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            if signedIn == false {
                PrimaryButton(title: "Log in to TikTok", systemImage: "person.fill") {
                    session.beginLogin()
                }
            } else if runner.isRunning {
                HStack(spacing: 10) {
                    QuietButton(title: runner.isPaused ? "Resume" : "Pause") {
                        runner.togglePause()
                    }
                    FilledButton(title: "Stop", fill: Theme.raised) {
                        confirmStop = true
                    }
                }
            } else if session.isWorking || awaitingFirstScan {
                PrimaryButton(title: "Looking for reposts", systemImage: "hourglass", enabled: false) {}
            } else if session.reposts.isEmpty {
                PrimaryButton(title: "Scan again", systemImage: "arrow.clockwise") {
                    Task { await session.loadReposts() }
                }
            } else {
                HStack(spacing: 10) {
                    QuietButton(title: "Refresh", systemImage: "arrow.clockwise") {
                        Task { await session.loadReposts() }
                    }
                    PrimaryButton(
                        title: removeTitle,
                        systemImage: "trash",
                        enabled: true
                    ) {
                        prepare(all: selectedItems.isEmpty || allSelected)
                    }
                }
                if selectedItems.isEmpty == false && allSelected == false {
                    Button("Remove all") {
                        prepare(all: true)
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.pink)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.canvas.ignoresSafeArea())
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    private var removeTitle: String {
        if selectedItems.isEmpty || allSelected {
            return "Remove all"
        }
        return "Remove selected"
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

private struct RepostRow: View {
    var item: RepostItem
    var image: UIImage?
    var selected: Bool
    var active: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                thumb
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.author.isEmpty ? item.titleLine : "@\(item.author)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                    if active {
                        Text("Removing")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.pink)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? Theme.pink : Theme.muted)
            }
            .padding(10)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(active ? Theme.pink : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.titleLine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var caption: String {
        let trimmed = item.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            return trimmed
        }
        return "Repost"
    }

    private var thumb: some View {
        ZStack {
            Theme.raised
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 56, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
