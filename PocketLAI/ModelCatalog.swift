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
    /// Parameter count shown in the picker, e.g. "1.7B".
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
    /// Built-in models, all 4-bit quantized. On an iPhone 17 Pro (12 GB RAM),
    /// models up to ~4B run smoothly. 7–8B models need the increased-memory entitlement.
    static let builtIn: [LMModel] = [
        // Qwen
        LMModel("Qwen3 0.6B", family: "Qwen", size: "0.6B", LLMRegistry.qwen3_0_6b_4bit),
        LMModel("Qwen3 1.7B", family: "Qwen", size: "1.7B", LLMRegistry.qwen3_1_7b_4bit),
        LMModel("Qwen3.5 2B", family: "Qwen", size: "2B", LLMRegistry.qwen3_5_2b_4bit),
        LMModel("Qwen3 4B", family: "Qwen", size: "4B", LLMRegistry.qwen3_4b_4bit),
        LMModel("Qwen3-VL 4B 👁", family: "Qwen", size: "4B", VLMRegistry.qwen3VL4BInstruct4Bit),
        LMModel("Qwen3 8B", family: "Qwen", size: "8B", LLMRegistry.qwen3_8b_4bit),

        // Gemma
        LMModel("Gemma 3 1B", family: "Gemma", size: "1B", LLMRegistry.gemma3_1B_qat_4bit),
        LMModel("Gemma 3 4B 👁", family: "Gemma", size: "4B", VLMRegistry.gemma3_4B_qat_4bit),
        LMModel("Gemma 3n E2B", family: "Gemma", size: "E2B", LLMRegistry.gemma3n_E2B_it_lm_4bit),
        LMModel("Gemma 3n E4B", family: "Gemma", size: "E4B", LLMRegistry.gemma3n_E4B_it_lm_4bit),
        LMModel("Gemma 4 E2B 👁", family: "Gemma", size: "E2B", VLMRegistry.gemma4_E2B_it_4bit),
        LMModel("Gemma 4 E4B 👁", family: "Gemma", size: "E4B", VLMRegistry.gemma4_E4B_it_4bit),

        // Llama
        LMModel("Llama 3.2 1B", family: "Llama", size: "1B", LLMRegistry.llama3_2_1B_4bit),
        LMModel("Llama 3.2 3B", family: "Llama", size: "3B", LLMRegistry.llama3_2_3B_4bit),
        LMModel("Llama 3.1 8B", family: "Llama", size: "8B", LLMRegistry.llama3_1_8B_4bit),

        // Others
        LMModel("SmolLM3 3B", family: "Other", size: "3B", LLMRegistry.smollm3_3b_4bit),
        LMModel("LFM2 1.2B", family: "Other", size: "1.2B", LLMRegistry.lfm2_1_2b_4bit),
        LMModel("LFM2.5-VL 1.6B 👁", family: "Other", size: "1.6B", VLMRegistry.lfm2_5_vl_1_6B_4bit),
        LMModel("Ministral 3 3B 👁", family: "Other", size: "3B", VLMRegistry.mistral3_3B_Instruct_4bit),
        LMModel("Phi 3.5 mini", family: "Other", size: "3.8B", LLMRegistry.phi3_5_4bit),
        LMModel("Granite 3.3 2B", family: "Other", size: "2B", LLMRegistry.granite3_3_2b_4bit),
        LMModel("DeepSeek R1 Distill 7B", family: "Other", size: "7B", LLMRegistry.deepSeekR1_7B_4bit),
    ]

    static let families = ["Qwen", "Gemma", "Llama", "Other"]
}
