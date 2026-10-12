import Foundation
import MLXLLM
import MLXLMCommon
import MLXVLM

/// A model the app can download from Hugging Face and run with MLX.
///
/// The app loads any MLX-format repo (e.g. anything under `mlx-community` whose
/// architecture mlx-swift-lm supports). The vision-model factory is tried first,
/// then the text-only one, so you don't have to say which kind a repo is.
struct LMModel: Identifiable, Hashable {
    let name: String
    let family: String
    /// Parameters and download size shown in the picker, e.g. "4B · 3.0 GB".
    let size: String
    let configuration: ModelConfiguration
    let isCustom: Bool

    var id: String { repoID }
    var repoID: String { configuration.name }

    init(_ name: String, family: String, size: String, _ configuration: ModelConfiguration) {
        self.name = name
        self.family = family
        self.size = size
        self.configuration = configuration
        self.isCustom = false
    }

    /// A model from any Hugging Face repo ID the user typed in.
    init(customRepoID repoID: String) {
        self.name = repoID.split(separator: "/").last.map(String.init) ?? repoID
        self.family = "Custom"
        self.size = ""
        // Reuse the built-in config (extra EOS tokens etc.) when the repo is a known one.
        self.configuration =
            VLMRegistry.shared.contains(id: repoID)
            ? VLMRegistry.shared.configuration(id: repoID)
            : LLMRegistry.shared.configuration(id: repoID)
        self.isCustom = true
    }

    static func == (lhs: LMModel, rhs: LMModel) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum ModelCatalog {
    /// Built-in models, all 4-bit. Sizes are the download size, which is roughly the RAM the model needs.
    /// On an iPhone 17 Pro (12 GB RAM), up to ~3 GB runs smoothly. 5–6 GB models rely on
    /// the increased-memory entitlement and leave little headroom.
    /// 👁 = vision model: accepts photos (all Qwen3.5 models are multimodal).
    static let builtIn: [LMModel] = [
        // Qwen 3.5, natively multimodal
        LMModel("Qwen3.5 2B 👁", family: "Qwen", size: "2B · 1.7 GB", LLMRegistry.qwen3_5_2b_4bit),
        LMModel("Qwen3.5 4B 👁", family: "Qwen", size: "4B · 3.0 GB", hub("mlx-community/Qwen3.5-4B-4bit", eos: ["<|im_end|>"])),

        // Gemma 4, multimodal
        LMModel("Gemma 4 E2B 👁", family: "Gemma", size: "E2B · 3.6 GB", VLMRegistry.gemma4_E2B_it_4bit),
        LMModel("Gemma 4 E4B 👁", family: "Gemma", size: "E4B · 5.2 GB", VLMRegistry.gemma4_E4B_it_4bit),

        // Mistral
        LMModel("Ministral 3 3B 👁", family: "Mistral", size: "3B · 2.8 GB", VLMRegistry.mistral3_3B_Instruct_4bit),

        // Others
        LMModel("Llama 3.2 3B", family: "Other", size: "3B · 1.8 GB", LLMRegistry.llama3_2_3B_4bit),
        LMModel("Phi-4 mini", family: "Other", size: "3.8B · 2.2 GB", hub("mlx-community/Phi-4-mini-instruct-4bit", eos: ["<|end|>"])),
        // The full DeepSeek R1 is 420 GB; this is the R1 reasoning model distilled into Qwen 7B.
        LMModel("DeepSeek R1 Distill 7B", family: "Other", size: "7B · 4.3 GB", LLMRegistry.deepSeekR1_7B_4bit),
    ]

    static let families = ["Qwen", "Gemma", "Mistral", "Other"]

    /// Pre-selected when the app starts.
    static let defaultModel = builtIn.first { $0.repoID == "mlx-community/Qwen3.5-2B-4bit" } ?? builtIn[0]

    /// A Hugging Face repo that isn't in mlx-swift-lm's built-in registry.
    private static func hub(_ id: String, eos: Set<String> = []) -> ModelConfiguration {
        ModelConfiguration(id: id, extraEOSTokens: eos)
    }
}
