import Foundation

public struct DoodleEntryStore {
    public private(set) var entries: [DoodleEntry]

    public init(entries: [DoodleEntry] = []) {
        self.entries = entries
    }

    @discardableResult
    public mutating func createEntry(
        id: UUID = UUID(),
        date: Date = Date()
    ) -> DoodleEntry {
        let entry = DoodleEntry(id: id, createdAt: date, updatedAt: date)
        entries.insert(entry, at: 0)
        return entry
    }

    public func entry(for id: UUID) -> DoodleEntry? {
        entries.first { $0.id == id }
    }

    @discardableResult
    public mutating func updateEntry(
        id: UUID,
        date: Date = Date(),
        thumbnailData: Data? = nil,
        updateThumbnail: Bool = false
    ) -> DoodleEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }

        var entry = entries[index]
        entry.updatedAt = date
        if updateThumbnail {
            entry.thumbnailData = thumbnailData
        }
        entries[index] = entry
        return entry
    }
}
