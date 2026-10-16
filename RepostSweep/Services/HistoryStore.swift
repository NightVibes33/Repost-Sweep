import Combine
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var lifetimeRemoved: Int = 0

    private let entriesKey = "removalHistory.v1"
    private let lifetimeKey = "lifetimeRemoved.v1"

    init() {
        let defaults = UserDefaults.standard
        lifetimeRemoved = max(0, defaults.integer(forKey: lifetimeKey))
        guard let data = defaults.data(forKey: entriesKey) else { return }
        if let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    func record(item: RepostItem, removed: Bool, detail: String) {
        let entry = HistoryEntry(
            id: UUID(),
            itemId: item.id,
            title: item.titleLine,
            author: item.author,
            date: Date(),
            removed: removed,
            detail: detail
        )
        entries.insert(entry, at: 0)
        if entries.count > 300 {
            entries = Array(entries.prefix(300))
        }
        if removed {
            lifetimeRemoved += 1
        }
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(lifetimeRemoved, forKey: lifetimeKey)
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: entriesKey)
        }
    }
}
