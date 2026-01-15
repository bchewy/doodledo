import XCTest

@testable import DoodleCore

final class DoodleEntryStoreTests: XCTestCase {
    func testCreateEntryInsertsAtTop() {
        var store = DoodleEntryStore()
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        let first = store.createEntry(id: firstID, date: Date(timeIntervalSince1970: 100))
        let second = store.createEntry(id: secondID, date: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries.first?.id, second.id)
        XCTAssertEqual(store.entries.last?.id, first.id)
    }

    func testEntryLookupReturnsEntry() {
        var store = DoodleEntryStore()
        let entryID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

        store.createEntry(id: entryID, date: Date(timeIntervalSince1970: 300))

        XCTAssertNotNil(store.entry(for: entryID))
        XCTAssertNil(store.entry(for: UUID()))
    }

    func testUpdateEntryTouchesTimestampAndThumbnail() {
        var store = DoodleEntryStore()
        let entryID = UUID(uuidString: "00000000-0000-0000-0000-000000000100")!
        let createdDate = Date(timeIntervalSince1970: 400)
        let updatedDate = Date(timeIntervalSince1970: 800)
        let thumbnail = Data([0x01, 0x02, 0x03])

        store.createEntry(id: entryID, date: createdDate)

        let updated = store.updateEntry(
            id: entryID,
            date: updatedDate,
            thumbnailData: thumbnail,
            updateThumbnail: true
        )

        XCTAssertEqual(updated?.updatedAt, updatedDate)
        XCTAssertEqual(updated?.thumbnailData, thumbnail)
    }
}
