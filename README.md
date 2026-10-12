<p align="center">
  <img src="docs/icon.svg" width="160" alt="Pockli app icon">
</p>

<h1 align="center">Pockli</h1>

<p align="center"><b>Local AI in your pocket.</b> Chat with open LLMs entirely on your iPhone. No cloud, no account, works offline.</p>

Pockli (Pocket Local Intelligence) is a SwiftUI chat app. It downloads open models from Hugging Face once, then runs them fully
on-device on the iPhone GPU with Apple's [MLX](https://github.com/ml-explore/mlx-swift) framework via
[mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm).
The design follows the MLX team's [MLXChatExample](https://github.com/ml-explore/mlx-swift-examples/tree/main/Applications/MLXChatExample),
which also handles both LLMs and vision models.

## Features
- **Any MLX model.** Built-in picks are a short list of current, well-tested models: Qwen3.5 2B/4B, Gemma 4 E2B/E4B, Ministral 3 3B, Llama 3.2 3B, Phi-4 mini and DeepSeek R1 Distill 7B.
  You can also paste any Hugging Face repo ID, for example `mlx-community/Ministral-3-3B-Reasoning-2512-4bit`.
- **Text and vision models load the same way.** The app tries the vision-model loader first, then the text-only one,
  so you never pick the type.
- **Photo input** for vision models (👁: Qwen3.5, Gemma 4, Ministral 3).
  On a text-only model, the photo button explains which models can see images.
- **Text in, text out.** Vision models can *read* images, but no model here *generates* images.
- **Rich replies.** Markdown (headings, lists, tables) and syntax-highlighted code blocks with a Copy button, rendered with [Textual](https://github.com/gonzalezreal/textual).
- **Streaming replies** with a Stop button, plus tokens/sec, context size and free memory under the chat.
- **Chat history.** Chats and their photos are saved on the phone. Reopening one restores its text as the model's context, even after switching models.
- **Background downloads.** Models download in an iOS background session, so the download keeps going with the screen off or the app in the background, resumes instead of restarting, and sends a notification when it's done.
- **Model manager.** See which models are downloaded (and how big), what's loaded, and swipe to delete.
- **Memory-safe photos.** Before each new photo, the context is rebuilt from text only, and messages are refused with a warning when free memory runs low (see Notes).
- **Liquid Glass UI** with light, dark or system appearance.
- **Thinking mode** for reasoning models. Their `<think>` output appears in a collapsible section.
- **Custom system prompt.**

## Requirements
- A Mac with Xcode 26 or newer (mlx-swift-lm needs Swift 6.2). No Homebrew or other tools are needed.
- An iPhone on **iOS 26 or newer** (the UI uses Liquid Glass).
- A physical iPhone. **MLX does not run in the iOS Simulator.**

## Build & run
```sh
git clone git@github.com:mgrossu/pockli.git
open pockli/Pockli.xcodeproj
```
1. Xcode fetches the Swift packages automatically. The first time takes a few minutes.
2. In the **Pockli** target, open **Signing & Capabilities** and pick your Team.
3. On the first build, Xcode asks you to **Trust & Enable** the `MLXHuggingFaceMacros` macro plugin. Accept it.
4. Plug in the iPhone, select it as the run destination, and press ⌘R.
   - On a first run, enable Developer Mode on the phone (Settings → Privacy & Security).
   - Then trust your developer certificate (Settings → General → VPN & Device Management).
5. Pick a model, then tap **Load**. The first load downloads the weights; after that the model works offline.

After that, the update loop is just `git pull`, then ⌘R. The project uses Xcode's synchronized folders,
so new files in `Pockli/` show up in Xcode automatically.

The shared scheme runs the **Release** configuration, because MLX is many times faster with optimizations on.
For breakpoints and step-through debugging, switch Run to Debug: Product → Scheme → Edit Scheme.

## Which models fit?
The iPhone 17 Pro has 12 GB of RAM. The picker shows each model's download size, which is roughly the RAM it needs:
- **Up to ~3 GB** (Qwen3.5 2B/4B, Ministral 3 3B, Llama 3.2 3B, Phi-4 mini) runs smoothly.
- **4–6 GB** (Gemma 4 E2B/E4B, DeepSeek R1 Distill 7B) needs the increased-memory entitlement and leaves less headroom.
- **Gemma 4 12B (11 GB) and larger** are too big for the phone. The full DeepSeek R1 is 420 GB.

## Project layout
| File | Purpose |
|---|---|
| `Pockli/ModelCatalog.swift` | Built-in model list. Add entries here. |
| `Pockli/ChatModel.swift` | Model loading (`loadModelContainer`), chat session, streaming, memory guard |
| `Pockli/Conversation.swift` | Chat and message types; saving chats and photos to disk |
| `Pockli/ModelDownloader.swift` | Background `URLSession` downloads from Hugging Face, resume, notification |
| `Pockli/ModelStorage.swift` | Where models live on disk; download status, size and deletion |
| `Pockli/ChatView.swift` | Chat screen, input bar, message bubbles, `<think>` rendering |
| `Pockli/MarkdownView.swift` | Markdown rendering and the code block card (Textual) |
| `Pockli/ModelsView.swift`, `HistoryView.swift`, `SettingsView.swift` | Models, Chats and Settings sheets |
| `Pockli/Theme.swift` | Brand colors and the appearance setting |
| `Pockli/Pockli.icon` | App icon (Icon Composer). `docs/icon.svg` is a flat preview of it for this README. |
| `Pockli.xcodeproj` | Xcode project: packages, build settings, entitlements, Info.plist keys |

## Notes
- **Free Apple ID:** if signing rejects `com.apple.developer.kernel.increased-memory-limit`, remove it from
  `Pockli/Pockli.entitlements`. Then stay at 4B or smaller.
- **Unsupported architectures:** a custom repo only loads if mlx-swift-lm supports its `model_type`.
  Otherwise the picker shows an "unsupported model type" error.
- **Where data lives:** chats and photos are in `Application Support/Chats`. Models are in `Application Support/Models`
  (excluded from iCloud backup). Models downloaded by older versions in `Library/Caches/huggingface/hub` are still used.
- **Why photos reset the context:** Gemma 4 and most vision models can't append a new photo to their cached context.
  The library would re-encode every photo in the chat at once, which crashed the app after about 3 photos.
  So before each new photo, the model's context is rebuilt from the chat's text only. Earlier photos stay visible,
  and the model keeps its own earlier descriptions of them.
