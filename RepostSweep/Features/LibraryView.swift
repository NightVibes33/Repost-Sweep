import SwiftUI
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var session: TikTokWebSession
    @EnvironmentObject private var purchases: PurchaseManager
    @EnvironmentObject private var freeTier: FreeTierStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    @StateObject private var runner = RemovalRunner()
    @State private var selected: Set<String> = []
    @State private var confirmRemove = false
    @State private var showPartial = false
    @State private var showPaywall = false
    @State private var showProgress = false
    @State private var showSiteChange = false
    @State private var pendingItems: [RepostItem] = []

    private var selectedItems: [RepostItem] {
        session.reposts.filter { selected.contains($0.id) }
    }

    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 5 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(LegalCopy.removals)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let banner = session.banner {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if session.isWorking && session.reposts.isEmpty {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(0..<9, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.raised)
                                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        }
                    }
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(session.statusText.isEmpty ? "Looking for reposts…" : session.statusText)
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                } else if session.reposts.isEmpty && session.isWorking == false {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(session.reposts) { item in
                            RepostCell(
                                item: item,
                                image: session.thumbnails[item.id],
                                selected: selected.contains(item.id)
                            ) {
                                toggle(item.id)
                            }
                            .task(id: item.id) {
                                await session.loadThumbnail(for: item)
                            }
                        }
                    }
                    if session.isWorking {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(session.statusText)
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .padding(16)
            .readableColumn()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Reposts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if session.reposts.isEmpty == false {
                    Button(allSelected ? "Clear" : "Select all") {
                        if allSelected {
                            selected.removeAll()
                        } else {
                            selected = Set(session.reposts.map(\.id))
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Rescan") {
                    Task { await session.loadReposts() }
                }
                .disabled(session.isWorking)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selectedItems.isEmpty == false {
                removalBar
            }
        }
        .refreshable {
            await session.loadReposts()
        }
        .confirmationDialog(
            "Remove \(pendingItems.count) reposts?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                begin(pendingItems)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears them from your reposts tab. The original videos stay up. Removals are spaced a few seconds apart.")
        }
        .confirmationDialog(
            "The free tier covers \(freeTier.remaining) more",
            isPresented: $showPartial,
            titleVisibility: .visible
        ) {
            Button("Remove \(freeTier.remaining) free") {
                pendingItems = Array(selectedItems.prefix(freeTier.remaining))
                confirmRemove = true
            }
            Button("See plans") {
                showPaywall = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You selected \(selectedItems.count). A subscription removes the cap.")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showSiteChange) {
            SiteChangeView()
        }
        .fullScreenCover(isPresented: $showProgress) {
            RemovalProgressView(runner: runner) {
                showProgress = false
                showPaywall = true
            } onClose: {
                showProgress = false
                if runner.siteChangeDetail != nil {
                    showSiteChange = true
                }
            }
        }
    }

    private var allSelected: Bool {
        session.reposts.isEmpty == false && selectedItems.count == session.reposts.count
    }

    private var emptyState: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(session.siteChangeMessage == nil ? "No reposts found" : "Couldn’t read the repost tab")
                    .font(Typeface.headline())
                    .foregroundStyle(Theme.ink)
                Text(
                    session.siteChangeMessage == nil
                        ? "This account’s repost tab looks empty. If you just reposted something, scan again in a minute."
                        : "TikTok’s page didn’t match what this version expects."
                )
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                if session.siteChangeMessage != nil {
                    QuietButton(title: "Why it stopped") {
                        showSiteChange = true
                    }
                }
            }
        }
    }

    private var removalBar: some View {
        VStack(spacing: 10) {
            PrimaryButton(
                title: "Remove \(selectedItems.count)",
                systemImage: "trash",
                enabled: session.isWorking == false && runner.isRunning == false
            ) {
                prepareRemoval()
            }
            .padding(.horizontal, 16)
            Text(purchases.isSubscribed ? "Unlimited with your subscription" : "\(freeTier.remaining) free left on this device")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.canvas.opacity(0.96))
    }

    private func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func prepareRemoval() {
        let chosen = selectedItems
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
        showPartial = true
    }

    private func begin(_ items: [RepostItem]) {
        guard items.isEmpty == false else { return }
        showProgress = true
        runner.start(items: items, session: session, freeTier: freeTier, purchases: purchases)
        selected.subtract(items.map(\.id))
    }
}

private struct RepostCell: View {
    var item: RepostItem
    var image: UIImage?
    var selected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottomLeading) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Theme.raised
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black.opacity(0.72)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    Text(item.titleLine)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                        .padding(8)
                }
                .clipped()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(selected ? Theme.accent : Color.white)
                    .shadow(color: Color.black.opacity(0.35), radius: 2, y: 1)
                    .padding(6)
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? Theme.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.titleLine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
