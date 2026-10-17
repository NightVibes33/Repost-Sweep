import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(history.lifetimeRemoved)")
                        .font(Typeface.hero)
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                        .numericTextTransition()
                    Text(history.lifetimeRemoved == 1 ? "repost removed" : "reposts removed")
                        .font(Typeface.body)
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

                if history.entries.isEmpty {
                    SurfaceCard {
                        Text("Removals you run show up here, on this device.")
                            .font(Typeface.secondary)
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(history.entries) { entry in
                            HistoryRow(entry: entry)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 24)
            .readableColumn()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Clear") {
                    confirmClear = true
                }
                .disabled(history.entries.isEmpty)
            }
        }
        .confirmationDialog("Clear history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                history.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The list on this screen goes away. The removed total stays.")
        }
    }
}

private struct HistoryRow: View {
    var entry: HistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.removed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(entry.removed ? Theme.success : Theme.pink)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.author.isEmpty ? entry.title : "@\(entry.author)")
                    .font(Typeface.secondary)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if entry.author.isEmpty == false {
                    Text(entry.title)
                        .font(Typeface.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                Text(subtitle)
                    .font(Typeface.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.cardPadding)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    private var subtitle: String {
        let stamp = entry.date.formatted(date: .abbreviated, time: .shortened)
        if entry.removed {
            return "Removed · \(stamp)"
        }
        if entry.detail.isEmpty {
            return "Stayed up · \(stamp)"
        }
        return "\(entry.detail) · \(stamp)"
    }
}
