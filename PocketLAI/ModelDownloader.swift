import Foundation
import UIKit
import UserNotifications

/// Downloads model files with a background `URLSession`.
///
/// iOS runs background-session transfers in a system process, so they keep going when
/// the screen turns off, the app is in the background, or iOS terminates the app. Files
/// that already finished are kept, so an interrupted download resumes instead of
/// starting over. When everything is done, iOS relaunches the app if needed and
/// ``AppDelegate`` hands us the completion handler.
final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = ModelDownloader()
    static let sessionIdentifier = "com.mgrossu.PocketLAI.model-downloads"

    /// Set by ``AppDelegate`` when iOS wakes the app for finished background transfers.
    var backgroundCompletionHandler: (() -> Void)?

    private struct Job {
        let name: String
        let directory: URL
        var remaining: Set<String>
        let sizes: [String: Int64]
        let totalBytes: Int64
        var finishedBytes: Int64
        var inFlight: [Int: Int64] = [:]
        let progress: @Sendable (Double) -> Void
        var continuation: CheckedContinuation<URL, Error>?
    }

    private let lock = NSLock()
    private var jobs: [String: Job] = [:]  // keyed by repo ID

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false  // start now, don't wait for Wi-Fi + charging
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    /// Recreates the background session so transfers from an earlier launch report back.
    func reconnect() { _ = session }

    // MARK: - Public API

    /// Returns the local folder for `repoID`, downloading whatever is missing first.
    func download(
        repoID: String, name: String, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        // Already complete: no network needed, works offline.
        if let local = ModelStorage.completeDirectory(for: repoID) { return local }
        // Downloaded by an earlier version of the app into the Hugging Face cache.
        if let legacy = ModelStorage.legacySnapshot(for: repoID) { return legacy }

        let directory = ModelStorage.localDirectory(for: repoID)
        let files: [ModelStorage.RemoteFile]
        if let saved = ModelStorage.manifest(for: repoID) {
            files = saved
        } else {
            files = try await Self.listFiles(repoID: repoID)
            try ModelStorage.saveManifest(files, for: repoID)
        }

        let missing = files.filter { !ModelStorage.hasFile($0, for: repoID) }
        if missing.isEmpty {
            ModelStorage.markComplete(repoID)
            return directory
        }
        await requestNotificationPermission()

        // Don't start a second transfer for files an earlier launch is still downloading.
        let running = Set(await session.allTasks.compactMap(\.taskDescription))
        let total = files.reduce(0) { $0 + $1.size }
        let done = total - missing.reduce(0) { $0 + $1.size }

        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                jobs[repoID]?.continuation?.resume(throwing: CancellationError())
                jobs[repoID] = Job(
                    name: name, directory: directory,
                    remaining: Set(missing.map(\.path)),
                    sizes: Dictionary(files.map { ($0.path, $0.size) }, uniquingKeysWith: { a, _ in a }),
                    totalBytes: max(total, 1), finishedBytes: done,
                    progress: progress, continuation: continuation)
            }
            progress(Double(done) / Double(max(total, 1)))
            for file in missing {
                let description = Self.describe(repoID: repoID, path: file.path)
                guard !running.contains(description) else { continue }
                let task = session.downloadTask(with: Self.url(repoID: repoID, path: file.path))
                task.taskDescription = description
                task.countOfBytesClientExpectsToReceive = file.size
                task.resume()
            }
        }
    }

    /// Stops any transfers for `repoID` (e.g. when the user deletes it).
    func cancel(repoID: String) async {
        for task in await session.allTasks {
            if case let (taskRepoID, _)? = task.taskDescription.flatMap(Self.parse), taskRepoID == repoID {
                task.cancel()
            }
        }
        fail(repoID: repoID, error: CancellationError())
    }

    // MARK: - URLSessionDownloadDelegate (called on a background queue)

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        guard case let (repoID, path)? = downloadTask.taskDescription.flatMap(Self.parse) else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            fail(repoID: repoID, error: DownloadError.http(status, path))
            return
        }
        // The temporary file is deleted when this method returns, so move it now.
        let destination = ModelStorage.localDirectory(for: repoID).appendingPathComponent(path)
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            fail(repoID: repoID, error: error)
            return
        }
        fileFinished(repoID: repoID, path: path, taskID: downloadTask.taskIdentifier)
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard case let (repoID, _)? = downloadTask.taskDescription.flatMap(Self.parse) else { return }
        let update: (@Sendable (Double) -> Void, Double)? = lock.withLock {
            guard var job = jobs[repoID] else { return nil }
            job.inFlight[downloadTask.taskIdentifier] = totalBytesWritten
            jobs[repoID] = job
            let bytes = job.finishedBytes + job.inFlight.values.reduce(0, +)
            return (job.progress, Double(bytes) / Double(job.totalBytes))
        }
        if case let (progress, fraction)? = update { progress(min(fraction, 1)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, case let (repoID, _)? = task.taskDescription.flatMap(Self.parse) else { return }
        if (error as? URLError)?.code == .cancelled { return }
        fail(repoID: repoID, error: error)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }

    // MARK: - Bookkeeping

    private func fileFinished(repoID: String, path: String, taskID: Int) {
        let finished: (Job, Bool)? = lock.withLock {
            guard var job = jobs[repoID] else { return nil }
            job.inFlight[taskID] = nil
            if job.remaining.remove(path) != nil {
                job.finishedBytes += job.sizes[path] ?? 0
            }
            let isDone = job.remaining.isEmpty
            jobs[repoID] = isDone ? nil : job
            return (job, isDone)
        }

        if case let (job, isDone)? = finished {
            job.progress(Double(job.finishedBytes) / Double(job.totalBytes))
            guard isDone else { return }
            ModelStorage.markComplete(repoID)
            job.continuation?.resume(returning: job.directory)
            notifyFinished(name: job.name)
        } else if ModelStorage.isFullyPresent(repoID) {
            // A transfer from an earlier launch completed while nobody was waiting on it.
            ModelStorage.markComplete(repoID)
        }
    }

    private func fail(repoID: String, error: Error) {
        let job: Job? = lock.withLock { jobs.removeValue(forKey: repoID) }
        job?.continuation?.resume(throwing: error)
    }

    private func notifyFinished(name: String) {
        DispatchQueue.main.async {
            guard UIApplication.shared.applicationState != .active else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(name) is ready"
            content.body = "The download finished. Open Pocket LAI to start chatting."
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    private func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    // MARK: - Hugging Face

    enum DownloadError: LocalizedError {
        case http(Int, String)
        case noFiles(String)

        var errorDescription: String? {
            switch self {
            case .http(401, _), .http(403, _):
                "This model requires a Hugging Face login, which Pocket LAI doesn't support."
            case .http(404, _):
                "Model not found on Hugging Face. Check the repo ID."
            case .http(let code, let path):
                "Download of \(path) failed (HTTP \(code))."
            case .noFiles(let repoID):
                "\(repoID) has no MLX weights (.safetensors) to download."
            }
        }
    }

    /// The files the model loader needs: weights, configs and chat templates.
    private static func listFiles(repoID: String) async throws -> [ModelStorage.RemoteFile] {
        struct Entry: Decodable {
            let type: String
            let path: String
            let size: Int64?
        }
        let url = URL(string: "https://huggingface.co/api/models/\(repoID)/tree/main?recursive=true")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw DownloadError.http(status, "file list") }
        let files = try JSONDecoder().decode([Entry].self, from: data)
            .filter { entry in
                entry.type == "file"
                    && [".safetensors", ".json", ".jinja"].contains { entry.path.hasSuffix($0) }
            }
            .map { ModelStorage.RemoteFile(path: $0.path, size: $0.size ?? 0) }
        guard files.contains(where: { $0.path.hasSuffix(".safetensors") }) else {
            throw DownloadError.noFiles(repoID)
        }
        return files
    }

    private static func url(repoID: String, path: String) -> URL {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(encoded)")!
    }

    private static func describe(repoID: String, path: String) -> String { "\(repoID)\n\(path)" }

    private static func parse(_ description: String) -> (repoID: String, path: String)? {
        let parts = description.split(separator: "\n", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }
}

/// Lets iOS deliver finished background downloads to the app.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == ModelDownloader.sessionIdentifier else {
            completionHandler()
            return
        }
        ModelDownloader.shared.backgroundCompletionHandler = completionHandler
        ModelDownloader.shared.reconnect()
    }
}
