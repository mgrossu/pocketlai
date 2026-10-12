import Foundation
import UIKit

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case user, assistant }

    var id = UUID()
    let role: Role
    var text: String
    /// File name of an attached photo inside ``ConversationStore/imagesDirectory``.
    var imageFile: String?
}

struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = "New chat"
    /// Display name of the model that answered last.
    var modelName: String?
    var createdAt = Date()
    var updatedAt = Date()
    var messages: [ChatMessage] = []
}

/// Saves chats as JSON files and their photos as JPEGs in Application Support.
@MainActor
final class ConversationStore {
    private let directory: URL
    let imagesDirectory: URL
    private let imageCache = NSCache<NSString, UIImage>()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("Chats", isDirectory: true)
        imagesDirectory = directory.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    /// All saved chats, newest first.
    func loadAll() -> [Conversation] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Conversation.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ conversation: Conversation) {
        guard let data = try? JSONEncoder().encode(conversation) else { return }
        try? data.write(to: file(for: conversation.id), options: .atomic)
    }

    func delete(_ conversation: Conversation) {
        for name in conversation.messages.compactMap(\.imageFile) {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
            imageCache.removeObject(forKey: name as NSString)
        }
        try? FileManager.default.removeItem(at: file(for: conversation.id))
    }

    /// Stores a photo, downscaled to at most 1024 px on its longest side. Returns its file name.
    func saveImage(_ image: UIImage) -> String? {
        let resized = image.downscaled(maxDimension: 1024)
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: imagesDirectory.appendingPathComponent(name), options: .atomic)
            imageCache.setObject(resized, forKey: name as NSString)
            return name
        } catch {
            return nil
        }
    }

    func image(named name: String) -> UIImage? {
        if let cached = imageCache.object(forKey: name as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: imagesDirectory.appendingPathComponent(name).path)
        else { return nil }
        imageCache.setObject(image, forKey: name as NSString)
        return image
    }

    private func file(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".json")
    }
}

extension UIImage {
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
