import PhotosUI
import SwiftUI

struct ChatView: View {
    @Environment(ChatModel.self) private var chat
    @State private var input = ""
    @State private var showSettings = false
    @State private var photoItem: PhotosPickerItem?
    @State private var attachedImage: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                if chat.isLoaded {
                    inputBar
                }
            }
            .navigationTitle(chat.isLoaded ? chat.selectedModel.name : "Pocket LLM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New", systemImage: "square.and.pencil") { chat.newSession() }
                        .disabled(!chat.isLoaded)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "slider.horizontal.3") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .presentationDetents([.medium, .large])
            }
            .onChange(of: photoItem) {
                guard let photoItem else { return }
                Task {
                    if let data = try? await photoItem.loadTransferable(type: Data.self) {
                        attachedImage = UIImage(data: data)
                    }
                    self.photoItem = nil
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch chat.loadState {
        case .loading(let fraction):
            VStack(spacing: 16) {
                ProgressView(value: fraction) {
                    Text(fraction < 1 ? "Downloading \(chat.selectedModel.name)…" : "Loading into memory…")
                } currentValueLabel: {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                }
                .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready where chat.isLoaded:
            messageList
        default:
            ModelPickerView()
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if chat.messages.isEmpty {
                        Text(chat.supportsImages
                             ? "Running fully on-device. Ask anything, or attach a photo."
                             : "Running fully on-device. Ask anything.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(chat.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if !chat.stats.isEmpty {
                        Text(chat.stats)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.last?.text) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let attachedImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: attachedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Button("Remove", systemImage: "xmark.circle.fill") { self.attachedImage = nil }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .offset(x: 6, y: -6)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                if chat.supportsImages {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                    }
                    .padding(.bottom, 4)
                }

                TextField("Message", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))

                if chat.isGenerating {
                    Button("Stop", systemImage: "stop.circle.fill") { chat.stop() }
                        .labelStyle(.iconOnly)
                        .font(.title)
                } else {
                    Button("Send", systemImage: "arrow.up.circle.fill") {
                        chat.send(input, image: attachedImage)
                        input = ""
                        attachedImage = nil
                    }
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Model picker

struct ModelPickerView: View {
    @Environment(ChatModel.self) private var chat
    @State private var customRepoID = ""

    var body: some View {
        List {
            if case .failed(let message) = chat.loadState {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await chat.load() }
                } label: {
                    Text("Load \(chat.selectedModel.name)")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text("Models download once from Hugging Face, then run offline on the GPU with MLX. 👁 = understands images. Up to ~4B runs smoothly on iPhone 17 Pro.")
            }

            ForEach(ModelCatalog.families, id: \.self) { family in
                Section(family) {
                    ForEach(ModelCatalog.builtIn.filter { $0.family == family }) { model in
                        row(for: model)
                    }
                }
            }

            Section {
                ForEach(chat.customModels) { model in
                    row(for: model)
                }
                .onDelete { chat.removeCustomModels(at: $0) }

                HStack {
                    TextField("mlx-community/model-name", text: $customRepoID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                    Button("Add") {
                        chat.addCustomModel(customRepoID)
                        customRepoID = ""
                    }
                    .disabled(!customRepoID.contains("/"))
                }
            } header: {
                Text("Any Hugging Face model")
            } footer: {
                Text("Paste the repo ID of any MLX model, e.g. from huggingface.co/mlx-community. Its architecture must be supported by mlx-swift-lm. Swipe to remove.")
            }
        }
    }

    private func row(for model: LMModel) -> some View {
        Button {
            chat.selectedModel = model
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).foregroundStyle(.primary)
                    Text(model.isCustom ? model.repoID : "\(model.size) · \(model.repoID)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if chat.selectedModel == model {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(ChatModel.self) private var chat
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var chat = chat
        NavigationStack {
            Form {
                Section("Model") {
                    LabeledContent("Current", value: chat.isLoaded ? chat.selectedModel.name : "None")
                    Button("Switch model…") {
                        chat.stop()
                        chat.loadState = .idle
                        dismiss()
                    }
                    .disabled(chat.isGenerating)
                }
                Section {
                    Toggle("Thinking mode", isOn: $chat.thinkingEnabled)
                } footer: {
                    Text("For models that support it (e.g. Qwen3): reason step by step before answering. Slower, but better on hard questions.")
                }
                Section("System prompt") {
                    TextField("System prompt", text: $chat.systemPrompt, axis: .vertical)
                        .lineLimit(2...6)
                    Button("Apply (starts a new chat)") { chat.newSession() }
                        .disabled(!chat.isLoaded)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Messages

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                if let image = message.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)
        case .assistant:
            let parts = ReplyParts(message.text)
            VStack(alignment: .leading, spacing: 8) {
                if let thinking = parts.thinking {
                    DisclosureGroup(parts.isThinking ? "Thinking…" : "Thought process") {
                        Text(thinking)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.footnote)
                    .tint(.secondary)
                }
                if parts.answer.isEmpty && !parts.isThinking {
                    ProgressView()
                } else if !parts.answer.isEmpty {
                    Text(LocalizedStringKey(parts.answer))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Splits a reply into its `<think>` section (Qwen3, DeepSeek R1, …) and the visible answer.
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
