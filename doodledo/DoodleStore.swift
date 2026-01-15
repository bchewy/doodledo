import Combine
import Foundation
import PencilKit
import UIKit

struct DoodleEntry: Identifiable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var caption: String
    var backgroundImageData: Data?
    var thumbnailData: Data?
}

final class DoodleStore: ObservableObject {
    @Published private(set) var entries: [DoodleEntry] = []
    private var drawings: [UUID: PKDrawing] = [:]

    func createEntry() -> DoodleEntry {
        let entry = DoodleEntry(
            id: UUID(),
            createdAt: Date(),
            updatedAt: Date(),
            caption: "",
            backgroundImageData: nil,
            thumbnailData: nil
        )
        entries.insert(entry, at: 0)
        return entry
    }

    func entry(for id: UUID) -> DoodleEntry? {
        entries.first { $0.id == id }
    }

    func loadDrawing(for id: UUID) -> PKDrawing {
        drawings[id] ?? PKDrawing()
    }

    func saveDrawing(_ drawing: PKDrawing, for id: UUID, generateThumbnail: Bool = false) {
        drawings[id] = drawing
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }

        var entry = entries[index]
        entry.updatedAt = Date()
        if generateThumbnail {
            entry.thumbnailData = makeThumbnailData(from: drawing, backgroundData: entry.backgroundImageData)
        }
        entries[index] = entry
    }

    func updateCaption(_ caption: String, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }

        var entry = entries[index]
        guard entry.caption != caption else { return }

        entry.caption = caption
        entry.updatedAt = Date()
        entries[index] = entry
    }

    func updateBackgroundImageData(_ data: Data?, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }

        var entry = entries[index]
        entry.backgroundImageData = data
        entry.updatedAt = Date()
        entries[index] = entry
    }

    private func makeThumbnailData(from drawing: PKDrawing, backgroundData: Data?) -> Data? {
        let hasDrawing = !drawing.bounds.isNull
        let backgroundImage = backgroundData.flatMap { UIImage(data: $0) }
        guard hasDrawing || backgroundImage != nil else { return nil }

        let padding: CGFloat = 24
        let rect: CGRect
        if let backgroundImage {
            rect = CGRect(origin: .zero, size: backgroundImage.size)
        } else {
            let bounds = drawing.bounds.insetBy(dx: -padding, dy: -padding)
            let width = max(bounds.width, 240)
            let height = max(bounds.height, 240)
            rect = CGRect(origin: bounds.origin, size: CGSize(width: width, height: height))
        }

        let renderer = UIGraphicsImageRenderer(size: rect.size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: rect.size))
            backgroundImage?.draw(in: CGRect(origin: .zero, size: rect.size))
            if hasDrawing {
                let drawingImage = drawing.image(from: rect, scale: UIScreen.main.scale)
                drawingImage.draw(in: CGRect(origin: .zero, size: rect.size))
            }
        }
        return image.pngData()
    }
}
