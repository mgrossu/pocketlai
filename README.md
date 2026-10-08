# PocketLLM: run LLMs on iPhone with MLX

PocketLLM is a SwiftUI chat app. It downloads open models from Hugging Face and runs them fully on-device on the
iPhone GPU with [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm).
The design follows Apple's [MLXChatExample](https://github.com/ml-explore/mlx-swift-examples/tree/main/Applications/MLXChatExample),
which also handles both LLMs and vision models.

## Features
- **Any MLX model.** Built-in picks cover Qwen, Gemma, Llama, SmolLM, LFM, Ministral, Phi, Granite and DeepSeek.
  You can also paste any Hugging Face repo ID, for example `mlx-community/gemma-3-12b-it-qat-4bit`.
- **Text and vision models load the same way.** The app tries the vision-model loader first, then the text-only one,
  so you never pick the type.
- **Photo input** for vision models (👁: Gemma 3/4, Qwen3-VL, LFM2.5-VL, Ministral 3).
- **Streaming replies** with a Stop button and tokens/sec stats.
- **Thinking mode** for reasoning models. Their `<think>` output appears in a collapsible section.
- **Custom system prompt.**

## Requirements
- A Mac with Xcode 26 or newer (iOS 18+ SDK).
- A physical iPhone. **MLX does not run in the iOS Simulator.**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build & run
```sh
cd pocketllm
xcodegen generate
open PocketLLM.xcodeproj
```
1. In Xcode, open target **PocketLLM**, then **Signing & Capabilities**. Pick your Team and set a unique bundle ID.
   You can also set `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`.
2. On the first build, Xcode asks you to **Trust & Enable** the `MLXHuggingFaceMacros` macro plugin. Accept it.
3. Select your iPhone and press ⌘R. On a first run, also enable Developer Mode on the phone.
4. Pick a model, then tap **Load**. The first load downloads the weights; after that the model works offline.

From the command line, use `xcodebuild ... -skipMacroValidation`.

## Which models fit?
The iPhone 17 Pro has 12 GB of RAM. Size estimates assume 4-bit weights:
- **Up to ~4B** (≈0.4–2.5 GB) runs smoothly.
- **7–8B** (≈4.5 GB) works only with the increased-memory entitlement, and leaves little headroom.
- **12B+** is too large for the phone.

## Project layout
| File | Purpose |
|---|---|
| `PocketLLM/ModelCatalog.swift` | Built-in model list. Add entries here. |
| `PocketLLM/ChatModel.swift` | Model loading (`loadModelContainer`), chat session, streaming, custom repos |
| `PocketLLM/ChatView.swift` | Model picker, chat UI, settings, `<think>` rendering |
| `project.yml` | XcodeGen spec: packages, entitlements, Info.plist keys |

## Notes
- **Free Apple ID:** if signing rejects `com.apple.developer.kernel.increased-memory-limit`, remove it from
  `project.yml` and `PocketLLM/PocketLLM.entitlements`. Then stay at 4B or smaller.
- **Speed:** Release builds are much faster than Debug builds. Use Edit Scheme → Run → Build Configuration → Release.
- **Unsupported architectures:** a custom repo only loads if mlx-swift-lm supports its `model_type`.
  Otherwise the picker shows an "unsupported model type" error.
