import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(history.lifetimeRemoved)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                    Text(history.lifetimeRemoved == 1 ? "repost removed" : "reposts removed")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

                if history.entries.isEmpty {
                    SurfaceCard {
                        Text("Removals you run show up here, on this device.")
                            .font(.subheadline)
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
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .readableColumn()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
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
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.author.isEmpty ? entry.title : "@\(entry.author)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if entry.author.isEmpty == false {
                    Text(entry.title)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
