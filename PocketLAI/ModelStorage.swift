import Foundation
import HuggingFace

/// Where model files live on the phone.
///
/// ``ModelDownloader`` saves each model in `Application Support/Models/<org>--<repo>/`,
/// excluded from iCloud backup. That folder holds a `manifest.json` (the files and sizes
/// to expect) and, once everything has arrived, a `.complete` marker.
///
/// Earlier app versions downloaded through swift-huggingface into
/// `Library/Caches/huggingface/hub/`; those downloads are still found and used.
enum ModelStorage {
    struct RemoteFile: Codable, Hashable {
        let path: String
        let size: Int64
    }

    private static let root: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var url = support.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Models are large and can be downloaded again, so keep them out of iCloud backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }()

    static func localDirectory(for repoID: String) -> URL {
        root.appendingPathComponent(repoID.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
    }

    /// The local folder, if the model finished downloading.
    static func completeDirectory(for repoID: String) -> URL? {
        let directory = localDirectory(for: repoID)
        let marker = directory.appendingPathComponent(".complete")
        return FileManager.default.fileExists(atPath: marker.path) ? directory : nil
    }

    // MARK: Manifest

    static func manifest(for repoID: String) -> [RemoteFile]? {
        let url = localDirectory(for: repoID).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([RemoteFile].self, from: data)
    }

    static func saveManifest(_ files: [RemoteFile], for repoID: String) throws {
        let directory = localDirectory(for: repoID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(files).write(to: directory.appendingPathComponent("manifest.json"))
    }

    /// True when `file` is on disk with the expected size.
    static func hasFile(_ file: RemoteFile, for repoID: String) -> Bool {
        let url = localDirectory(for: repoID).appendingPathComponent(file.path)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber
        else { return false }
        return file.size == 0 || size.int64Value == file.size
    }

    static func isFullyPresent(_ repoID: String) -> Bool {
        guard let files = manifest(for: repoID) else { return false }
        return files.allSatisfy { hasFile($0, for: repoID) }
    }

    static func markComplete(_ repoID: String) {
        let marker = localDirectory(for: repoID).appendingPathComponent(".complete")
        FileManager.default.createFile(atPath: marker.path, contents: Data())
    }

    // MARK: Size and deletion

    /// Bytes on disk for a fully downloaded model, or nil if it isn't downloaded.
    static func downloadedSize(of repoID: String) -> Int64? {
        if let directory = completeDirectory(for: repoID) { return size(of: directory) }
        if legacySnapshot(for: repoID) != nil, let legacy = legacyDirectory(for: repoID) {
            return size(of: legacy.appendingPathComponent("blobs"))
        }
        return nil
    }

    /// Removes the model from both the app's folder and the old Hugging Face cache.
    static func delete(_ repoID: String) throws {
        for directory in [localDirectory(for: repoID), legacyDirectory(for: repoID)].compactMap({ $0 })
        where FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
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

    // MARK: Legacy Hugging Face cache

    private static func legacyDirectory(for repoID: String) -> URL? {
        guard let id = Repo.ID(rawValue: repoID) else { return nil }
        return HubCache.default.repoDirectory(repo: id, kind: .model)
    }

    /// A complete snapshot from an earlier app version: has a config and resolvable weights.
    static func legacySnapshot(for repoID: String) -> URL? {
        guard let directory = legacyDirectory(for: repoID) else { return nil }
        let fileManager = FileManager.default
        let revisions = (try? fileManager.contentsOfDirectory(
            at: directory.appendingPathComponent("snapshots"), includingPropertiesForKeys: nil)) ?? []
        return revisions.first { revision in
            let files = (try? fileManager.contentsOfDirectory(atPath: revision.path)) ?? []
            return files.contains("config.json")
                && files.contains { name in
                    // Snapshot entries are symlinks into blobs/; fileExists follows them.
                    name.hasSuffix(".safetensors")
                        && fileManager.fileExists(atPath: revision.appendingPathComponent(name).path)
                }
        }
    }
}
