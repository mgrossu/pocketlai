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

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }

    let id = UUID()
    let role: Role
    var text: String
    var image: UIImage?
}

@MainActor
@Observable
final class ChatModel {
    enum LoadState: Equatable {
        case idle
        case loading(Double)
        case ready
        case failed(String)
    }

    var selectedModel: LMModel = ModelCatalog.builtIn[1]
    var customModels: [LMModel] = []
    var loadState: LoadState = .idle
    var messages: [ChatMessage] = []
    var isGenerating = false
    var stats = ""
    var systemPrompt = "You are a helpful assistant running locally on an iPhone."
    /// True when the loaded model accepts images (a vision-language model).
    private(set) var supportsImages = false

    /// Models that support it (e.g. Qwen3) "think" in <think>…</think> before answering.
    var thinkingEnabled = false {
        didSet { session?.additionalContext = ["enable_thinking": thinkingEnabled] }
    }

    private var container: ModelContainer?
    private var session: ChatSession?
    private var loadedModel: LMModel?
    private var generationTask: Task<Void, Never>?

    private static let customModelsKey = "customModelRepoIDs"

    init() {
        // Keep MLX's buffer cache small so memory is returned to the system between turns.
        Memory.cacheLimit = 32 * 1024 * 1024
        let saved = UserDefaults.standard.stringArray(forKey: Self.customModelsKey) ?? []
        customModels = saved.map(LMModel.init(customRepoID:))
    }

    var isLoaded: Bool { loadState == .ready && loadedModel == selectedModel }

    // MARK: - Custom models

    /// Adds any Hugging Face repo ID, e.g. "mlx-community/gemma-3-12b-it-qat-4bit".
    func addCustomModel(_ repoID: String) {
        let repoID = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard repoID.contains("/"), !customModels.contains(where: { $0.repoID == repoID }) else {
            return
        }
        let model = LMModel(customRepoID: repoID)
        customModels.append(model)
        selectedModel = model
        saveCustomModels()
    }

    func removeCustomModels(at offsets: IndexSet) {
        customModels.remove(atOffsets: offsets)
        saveCustomModels()
    }

    private func saveCustomModels() {
        UserDefaults.standard.set(customModels.map(\.repoID), forKey: Self.customModelsKey)
    }

    // MARK: - Loading

    /// Downloads the selected model (first time only) and loads it onto the GPU.
    func load() async {
        let model = selectedModel
        if loadedModel == model, container != nil {
            loadState = .ready  // already in memory (e.g. user reopened the picker)
            return
        }

        stop()
        // Release the previous model before loading the next, so two never sit in memory.
        container = nil
        session = nil
        loadedModel = nil
        supportsImages = false
        messages = []
        stats = ""
        Memory.clearCache()
        loadState = .loading(0)

        do {
            // Tries the vision-model factory, then the text-only one, so any
            // supported architecture (Gemma, Llama, Qwen, Phi, Mistral…) loads.
            let container = try await loadModelContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: model.configuration,
                progressHandler: { progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor [weak self] in
                        guard let self, case .loading = self.loadState else { return }
                        self.loadState = .loading(fraction)
                    }
                }
            )
            guard selectedModel == model else {
                loadState = .idle  // user picked another model meanwhile
                return
            }
            self.container = container
            self.loadedModel = model
            self.supportsImages = await container.perform { $0.model is any VLMModel }
            newSession()
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Chat

    /// Starts a fresh conversation with the loaded model.
    func newSession() {
        stop()
        messages = []
        stats = ""
        guard let container else { return }

        var parameters = GenerateParameters()
        parameters.temperature = 0.7
        parameters.topP = 0.9
        parameters.maxTokens = 2048

        session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: parameters,
            additionalContext: ["enable_thinking": thinkingEnabled]
        )
    }

    func send(_ text: String, image: UIImage? = nil) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session, !prompt.isEmpty, !isGenerating else { return }

        var images: [UserInput.Image] = []
        if supportsImages, let cgImage = image?.cgImage {
            images.append(.ciImage(CIImage(cgImage: cgImage)))
        }

        messages.append(ChatMessage(role: .user, text: prompt, image: images.isEmpty ? nil : image))
        messages.append(ChatMessage(role: .assistant, text: ""))
        let replyID = messages[messages.count - 1].id
        isGenerating = true
        stats = ""

        generationTask = Task {
            do {
                for try await item in session.streamDetails(to: prompt, images: images) {
                    switch item {
                    case .chunk(let chunk):
                        append(chunk, to: replyID)
                    case .info(let info):
                        let tps = Double(info.generationTokenCount) / max(info.generateTime, 0.001)
                        stats = String(
                            format: "%d tokens · %.1f tok/s · prompt %.2fs",
                            info.generationTokenCount, tps, info.promptTime)
                    default:
                        break
                    }
                }
            } catch is CancellationError {
                // stopped by the user
            } catch {
                append("\n\n⚠️ \(error.localizedDescription)", to: replyID)
            }
            // stop() already reset state for a cancelled run; don't clobber a newer one.
            if !Task.isCancelled { isGenerating = false }
        }
    }

    func stop() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    private func append(_ chunk: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += chunk
    }
}
