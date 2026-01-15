import Foundation

public struct DoodleEntry: Identifiable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public var updatedAt: Date
    public var thumbnailData: Data?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        thumbnailData: Data? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.thumbnailData = thumbnailData
    }
}
