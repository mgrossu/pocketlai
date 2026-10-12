import Foundation
import HuggingFace

/// Finds and deletes downloaded model files.
///
/// Models are downloaded by swift-huggingface into its Python-compatible cache,
/// which on iOS is `Library/Caches/huggingface/hub/models--<org>--<repo>/`.
/// iOS may purge Caches when the device runs low on storage; the model is then
/// simply downloaded again on the next load.
enum ModelStorage {
    static func directory(for repoID: String) -> URL? {
        guard let id = Repo.ID(rawValue: repoID) else { return nil }
        return HubCache.default.repoDirectory(repo: id, kind: .model)
    }

    /// Bytes on disk for a fully downloaded model, or nil if it isn't downloaded.
    static func downloadedSize(of repoID: String) -> Int64? {
        guard let directory = directory(for: repoID), isComplete(directory) else { return nil }
        return size(of: directory.appendingPathComponent("blobs"))
    }

    static func delete(_ repoID: String) throws {
        guard let directory = directory(for: repoID),
            FileManager.default.fileExists(atPath: directory.path)
        else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// A snapshot counts as complete when it has a config and at least one weights file.
    private static func isComplete(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        let snapshots = directory.appendingPathComponent("snapshots")
        let revisions = (try? fileManager.contentsOfDirectory(
            at: snapshots, includingPropertiesForKeys: nil)) ?? []
        return revisions.contains { revision in
            let files = (try? fileManager.contentsOfDirectory(atPath: revision.path)) ?? []
            return files.contains("config.json")
                && files.contains { name in
                    // Snapshot entries are symlinks into blobs/; fileExists follows them.
                    name.hasSuffix(".safetensors")
                        && fileManager.fileExists(atPath: revision.appendingPathComponent(name).path)
                }
        }
    }

    private static func size(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys)
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true
            else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
