import CoreImage
import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import MLXVLM
import Tokenizers
import UIKit
import os

@MainActor
@Observable
final class ChatModel {
    enum LoadState: Equatable {
        case idle
        case loading(Double)
        case ready
        case failed(String)
    }

    // MARK: Models

    var selectedModel: LMModel = ModelCatalog.defaultModel
    var customModels: [LMModel] = []
    var loadState: LoadState = .idle
    private(set) var loadedModel: LMModel?
    /// True when the loaded model accepts images (a vision-language model).
    private(set) var supportsImages = false
    /// Bytes on disk per downloaded repo ID. Refreshed with ``refreshDownloads()``.
    private(set) var downloadedSizes: [String: Int64] = [:]

    // MARK: Chat

    private(set) var conversation = Conversation()
    private(set) var conversations: [Conversation] = []
    var messages: [ChatMessage] { conversation.messages }
    private(set) var isGenerating = false
    private(set) var stats = ""
    /// Tokens the model is currently holding as context for this chat.
    private(set) var contextTokens = 0
    /// Set when a message is refused because the phone is low on memory.
    var memoryWarning: String?

    // MARK: Settings (persisted)

    var systemPrompt: String {
        didSet {
            defaults.set(systemPrompt, forKey: Keys.systemPrompt)
            session = nil  // rebuilt with the new instructions on the next message
        }
    }

    /// Models that support it (e.g. Qwen3.5, DeepSeek R1) reason in <think>…</think> first.
    var thinkingEnabled: Bool {
        didSet {
            defaults.set(thinkingEnabled, forKey: Keys.thinking)
            session?.additionalContext = ["enable_thinking": thinkingEnabled]
        }
    }

    let store = ConversationStore()
    private var container: ModelContainer?
    private var session: ChatSession?
    /// Whether `session`'s transcript already contains a photo. See ``send(_:image:)``.
    private var sessionHasImage = false
    private var generationTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let customModels = "customModelRepoIDs"
        static let systemPrompt = "systemPrompt"
        static let thinking = "thinkingEnabled"
    }

    init() {
        // Keep MLX's buffer cache small so memory is returned to the system between turns.
        Memory.cacheLimit = 32 * 1024 * 1024
        systemPrompt = UserDefaults.standard.string(forKey: Keys.systemPrompt)
            ?? "You are a helpful assistant running locally on an iPhone."
        thinkingEnabled = UserDefaults.standard.bool(forKey: Keys.thinking)
        customModels = (UserDefaults.standard.stringArray(forKey: Keys.customModels) ?? [])
            .map(LMModel.init(customRepoID:))
        conversations = store.loadAll()
        refreshDownloads()
        // Hear back from downloads that kept running while the app was closed.
        ModelDownloader.shared.reconnect()
    }

    var isLoaded: Bool { loadState == .ready && loadedModel != nil }

    /// Memory the OS still lets this app allocate before it gets terminated.
    var availableMemory: Int64 { Int64(os_proc_available_memory()) }

    // MARK: - Custom models

    /// Adds any Hugging Face repo ID, e.g. "mlx-community/Qwen3.5-0.8B-4bit".
    func addCustomModel(_ repoID: String) {
        let repoID = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard repoID.contains("/"), !customModels.contains(where: { $0.repoID == repoID }) else {
            return
        }
        customModels.append(LMModel(customRepoID: repoID))
        saveCustomModels()
    }

    func removeCustomModel(_ model: LMModel) {
        customModels.removeAll { $0 == model }
        saveCustomModels()
    }

    private func saveCustomModels() {
        defaults.set(customModels.map(\.repoID), forKey: Keys.customModels)
    }

    // MARK: - Downloads

    func refreshDownloads() {
        var sizes: [String: Int64] = [:]
        for model in ModelCatalog.builtIn + customModels {
            if let size = ModelStorage.downloadedSize(of: model.repoID) {
                sizes[model.repoID] = size
            }
        }
        downloadedSizes = sizes
    }

    func isDownloaded(_ model: LMModel) -> Bool { downloadedSizes[model.repoID] != nil }

    /// Deletes a model's files, unloading it first if it's the one in memory.
    func deleteDownload(of model: LMModel) {
        if loadedModel == model { unload() }
        Task {
            await ModelDownloader.shared.cancel(repoID: model.repoID)
            try? ModelStorage.delete(model.repoID)
            refreshDownloads()
        }
    }

    // MARK: - Loading

    /// Downloads `model` (first time only) and loads it onto the GPU.
    /// The current chat is kept; the new model continues it.
    func load(_ model: LMModel) async {
        selectedModel = model
        if loadedModel == model, container != nil {
            loadState = .ready
            return
        }

        // Release the previous model before loading the next, so two never sit in memory.
        unload()
        loadState = .loading(0)

        do {
            // Downloads in a background URLSession, so it continues with the screen off
            // or the app in the background, and resumes instead of restarting.
            let directory = try await ModelDownloader.shared.download(
                repoID: model.repoID, name: model.name,
                progress: { fraction in
                    // ChatModel lives as long as the app, so a strong capture is fine here.
                    Task { @MainActor in
                        guard case .loading = self.loadState else { return }
                        self.loadState = .loading(min(fraction, 0.999))
                    }
                }
            )
            // iOS forbids GPU work in the background. If the download finished while
            // the app was in the background, wait until it's open again to load.
            await waitUntilActive()
            loadState = .loading(1)

            // Load from the local folder. Tries the vision-model factory, then the
            // text-only one, so any supported architecture (Gemma, Llama, Qwen…) loads.
            var configuration = model.configuration
            configuration.id = .directory(directory)
            let container = try await loadModelContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: configuration
            )
            guard selectedModel == model else {
                loadState = .idle  // user picked another model meanwhile
                return
            }
            self.container = container
            self.loadedModel = model
            self.supportsImages = await container.perform { $0.model is any VLMModel }
            loadState = .ready
        } catch is CancellationError {
            if selectedModel == model { loadState = .idle }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
        refreshDownloads()
    }

    /// Called when the app leaves the screen: iOS doesn't allow GPU work in the background.
    func didEnterBackground() {
        stop()
    }

    private func waitUntilActive() async {
        guard UIApplication.shared.applicationState != .active else { return }
        for await _ in NotificationCenter.default.notifications(
            named: UIApplication.didBecomeActiveNotification)
        {
            break
        }
    }

    func unload() {
        stop()
        session = nil
        sessionHasImage = false
        container = nil
        loadedModel = nil
        supportsImages = false
        contextTokens = 0
        loadState = .idle
        Memory.clearCache()
    }

    // MARK: - Conversations

    func newChat() {
        stop()
        conversation = Conversation()
        resetSession()
    }

    func open(_ saved: Conversation) {
        stop()
        conversation = saved
        resetSession()
    }

    func delete(_ saved: Conversation) {
        store.delete(saved)
        conversations.removeAll { $0.id == saved.id }
        if conversation.id == saved.id {
            stop()
            conversation = Conversation()
            resetSession()
        }
    }

    func deleteAllChats() {
        stop()
        for saved in conversations { store.delete(saved) }
        conversations = []
        conversation = Conversation()
        resetSession()
    }

    /// Drops the model's context. The next message rebuilds it from the chat's text.
    private func resetSession() {
        session = nil
        sessionHasImage = false
        contextTokens = 0
        stats = ""
        Memory.clearCache()
    }

    private func persist() {
        guard !conversation.messages.isEmpty else { return }
        conversation.updatedAt = Date()
        store.save(conversation)
        conversations.removeAll { $0.id == conversation.id }
        conversations.insert(conversation, at: 0)
    }

    // MARK: - Chat

    func send(_ text: String, image: UIImage? = nil) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let container, !prompt.isEmpty, !isGenerating else { return }
        let image = supportsImages ? image : nil

        // Refuse instead of letting iOS kill the app when memory is nearly exhausted.
        Memory.clearCache()
        let needed: Int64 = image == nil ? 400_000_000 : 900_000_000
        guard availableMemory > needed else {
            memoryWarning =
                "Only \(availableMemory.formatted(.byteCount(style: .memory))) of memory is left. "
                + "Start a new chat to free the model's context, or switch to a smaller model."
            return
        }

        // Vision models like Gemma 4 can't append a new photo to their cached context:
        // the library re-encodes *every* photo in the transcript on each new photo, which
        // runs the phone out of memory after a few. So before sending another photo,
        // rebuild the context from the chat's text only. Earlier photos stay visible in
        // the chat, and the model still has its own earlier descriptions of them.
        if image != nil, sessionHasImage { resetSession() }
        let activeSession = session ?? makeSession(container)

        var images: [UserInput.Image] = []
        var imageFile: String?
        if let image, let cgImage = image.downscaled(maxDimension: 1024).cgImage {
            images.append(.ciImage(CIImage(cgImage: cgImage)))
            imageFile = store.saveImage(image)
            sessionHasImage = true
        }

        if conversation.messages.isEmpty {
            conversation.title = String(prompt.prefix(60))
        }
        conversation.modelName = loadedModel?.name
        conversation.messages.append(ChatMessage(role: .user, text: prompt, imageFile: imageFile))
        conversation.messages.append(ChatMessage(role: .assistant, text: ""))
        let replyID = conversation.messages[conversation.messages.count - 1].id
        isGenerating = true
        stats = ""
        persist()

        generationTask = Task {
            // Tokens arrive 20–40 times a second. Re-rendering the Markdown that often
            // makes the reply flicker, so hand them to the UI in batches (~10 per second).
            var pending = ""
            var lastFlush = ContinuousClock.now
            @MainActor func flush() {
                guard !pending.isEmpty else { return }
                append(pending, to: replyID)
                pending = ""
                lastFlush = .now
            }
            do {
                for try await item in activeSession.streamDetails(to: prompt, images: images) {
                    switch item {
                    case .chunk(let chunk):
                        pending += chunk
                        if ContinuousClock.now - lastFlush > .milliseconds(100) { flush() }
                    case .info(let info):
                        flush()
                        contextTokens = info.promptTokenCount + info.generationTokenCount
                        let tps = Double(info.generationTokenCount) / max(info.generateTime, 0.001)
                        stats = String(format: "%.1f tok/s", tps)
                    default:
                        break
                    }
                }
            } catch is CancellationError {
                // stopped by the user
            } catch {
                flush()
                append("\n\n⚠️ \(error.localizedDescription)", to: replyID)
            }
            flush()
            // stop() already reset state for a cancelled run; don't clobber a newer one.
            if !Task.isCancelled {
                isGenerating = false
                generationTask = nil
            }
            persist()  // also saves the last batch of a stopped reply
        }
    }

    func stop() {
        guard let generationTask else { return }
        generationTask.cancel()
        self.generationTask = nil
        isGenerating = false
        persist()  // keep the partial reply
    }

    /// Creates the model session, restoring this chat's earlier turns as context
    /// (text only: thinking sections and photos are left out to save memory).
    private func makeSession(_ container: ModelContainer) -> ChatSession {
        var parameters = GenerateParameters()
        parameters.temperature = 0.7
        parameters.topP = 0.9
        parameters.maxTokens = 2048

        let history: [Chat.Message] = conversation.messages.compactMap { message in
            let text = message.role == .assistant ? ReplyParts(message.text).answer : message.text
            guard !text.isEmpty else { return nil }
            return Chat.Message(role: message.role == .user ? .user : .assistant, content: text)
        }

        let newSession = ChatSession(
            container,
            instructions: systemPrompt,
            history: history,
            generateParameters: parameters,
            additionalContext: ["enable_thinking": thinkingEnabled]
        )
        session = newSession
        sessionHasImage = false
        return newSession
    }

    private func append(_ chunk: String, to id: UUID) {
        guard let index = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        conversation.messages[index].text += chunk
    }
}

/// Splits a reply into its `<think>` section (Qwen3.5, DeepSeek R1, …) and the visible answer.
struct ReplyParts {
    var thinking: String?
    var answer: String
    var isThinking = false

    init(_ text: String) {
        var text = text
        if let open = text.range(of: "<think>") {
            text.removeSubrange(text.startIndex..<open.upperBound)
            if text.range(of: "</think>") == nil {
                // Still inside the thinking block.
                thinking = text.trimmingCharacters(in: .whitespacesAndNewlines)
                answer = ""
                isThinking = true
                return
            }
        }
        if let close = text.range(of: "</think>") {
            let thought = text[..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            thinking = thought.isEmpty ? nil : thought
            answer = text[close.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
