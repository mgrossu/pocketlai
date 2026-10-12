import PhotosUI
import SwiftUI

struct ChatView: View {
    enum Sheet: String, Identifiable {
        case models, history, settings
        var id: String { rawValue }
    }

    @Environment(ChatModel.self) private var chat
    @State private var input = ""
    @State private var sheet: Sheet?
    @State private var photoItem: PhotosPickerItem?
    @State private var attachedImage: UIImage?
    @State private var showImageHint = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            // The input bar is the last item of the stack (not an overlay), so the
            // whole stack shrinks above the keyboard and the bar is never covered.
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .models: ModelsView()
                case .history: HistoryView()
                case .settings: SettingsView().presentationDetents([.medium, .large])
                }
            }
            .alert("Low memory", isPresented: memoryWarningShown) {
                Button("New chat") { chat.newChat() }
                Button("OK", role: .cancel) {}
            } message: {
                Text(chat.memoryWarning ?? "")
            }
            .alert("This model can't see images", isPresented: $showImageHint) {
                Button("Choose model") { sheet = .models }
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(chat.loadedModel?.name ?? "This model") is text-only. Pick a model marked 👁, such as Qwen3.5 2B, Gemma 4 E2B or Ministral 3 3B, to chat about photos.")
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

    private var memoryWarningShown: Binding<Bool> {
        Binding(
            get: { chat.memoryWarning != nil },
            set: { if !$0 { chat.memoryWarning = nil } }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Chats", systemImage: "clock.arrow.circlepath") { sheet = .history }
        }
        ToolbarItem(placement: .principal) {
            Button { sheet = .models } label: {
                HStack(spacing: 4) {
                    Text(chat.loadedModel?.name ?? "Choose model")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("New chat", systemImage: "square.and.pencil") { chat.newChat() }
                .disabled(chat.messages.isEmpty)
            Button("Settings", systemImage: "gearshape") { sheet = .settings }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        Group {
            mainContent
        }
        // Tapping outside the input field hides the keyboard.
        .contentShape(.rect)
        .onTapGesture { inputFocused = false }
    }

    @ViewBuilder
    private var mainContent: some View {
        if case .loading(let fraction) = chat.loadState {
            LoadingCard(modelName: chat.selectedModel.name, fraction: fraction)
        } else if !chat.messages.isEmpty {
            MessageList()
        } else if chat.isLoaded {
            EmptyChatView {
                input = $0
                inputFocused = true
            }
        } else {
            WelcomeView(openModels: { sheet = .models })
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if chat.isLoaded {
            inputBar
        } else if case .loading = chat.loadState {
            EmptyView()
        } else if !chat.messages.isEmpty {
            // A saved chat is open but no model is in memory.
            Button {
                Task { await chat.load(chat.selectedModel) }
            } label: {
                Label("Load \(chat.selectedModel.name) to continue", systemImage: "bolt.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let attachedImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: attachedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 10))
                    Button("Remove", systemImage: "xmark.circle.fill") { self.attachedImage = nil }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .offset(x: 6, y: -6)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                photoButton

                TextField("Ask anything", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
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
                        inputFocused = false
                    }
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .disabled(!canSend)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var photoButton: some View {
        Group {
            if chat.supportsImages {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                }
            } else {
                // Text-only model: explain instead of silently hiding the button.
                Button("Attach photo", systemImage: "photo.badge.plus") { showImageHint = true }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.title2)
        .padding(.bottom, 4)
        .accessibilityLabel("Attach photo")
    }
}

// MARK: - Messages

struct MessageList: View {
    @Environment(ChatModel.self) private var chat

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(chat.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    StatusLine()
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.last?.text) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

/// Speed, context size and free memory, so you can see when a chat is getting heavy.
struct StatusLine: View {
    @Environment(ChatModel.self) private var chat

    var body: some View {
        let parts = [
            chat.stats.isEmpty ? nil : chat.stats,
            chat.contextTokens > 0 ? "\(Self.compact(chat.contextTokens)) tokens in context" : nil,
            chat.isLoaded
                ? "\(chat.availableMemory.formatted(.byteCount(style: .memory))) free" : nil,
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    static func compact(_ count: Int) -> String {
        count < 1000 ? "\(count)" : String(format: "%.1fk", Double(count) / 1000)
    }
}

struct MessageBubble: View {
    @Environment(ChatModel.self) private var chat
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                if let name = message.imageFile, let image = chat.store.image(named: name) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipShape(.rect(cornerRadius: 18))
                }
                Text(message.text)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18))
                    .contextMenu { copyButton(message.text) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 48)

        case .assistant:
            let parts = ReplyParts(message.text)
            VStack(alignment: .leading, spacing: 10) {
                if let thinking = parts.thinking {
                    DisclosureGroup {
                        Text(thinking)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    } label: {
                        Label(parts.isThinking ? "Thinking…" : "Thought process", systemImage: "brain")
                            .font(.footnote.weight(.medium))
                    }
                    .tint(.secondary)
                }
                if parts.answer.isEmpty && !parts.isThinking {
                    ProgressView()
                } else if !parts.answer.isEmpty {
                    MarkdownView(markdown: parts.answer)
                    if !isStreaming {
                        Button {
                            UIPasteboard.general.string = parts.answer
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// True while this is the reply currently being generated.
    private var isStreaming: Bool {
        chat.isGenerating && chat.messages.last?.id == message.id
    }

    private func copyButton(_ text: String) -> some View {
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
    }
}

// MARK: - Empty states

struct WelcomeView: View {
    @Environment(ChatModel.self) private var chat
    let openModels: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text("Pocket LAI").font(.largeTitle.bold())
                Text("Private AI that runs entirely on your iPhone.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if case .failed(let message) = chat.loadState {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            VStack(spacing: 12) {
                Button {
                    Task { await chat.load(chat.selectedModel) }
                } label: {
                    Label(
                        chat.isDownloaded(chat.selectedModel)
                            ? "Start with \(chat.selectedModel.name)"
                            : "Download \(chat.selectedModel.name) · \(chat.selectedModel.size)",
                        systemImage: "bolt.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: openModels) {
                    Label("Choose another model", systemImage: "square.stack.3d.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
        .padding()
    }
}

struct EmptyChatView: View {
    @Environment(ChatModel.self) private var chat
    let suggest: (String) -> Void

    private let suggestions = [
        "Explain how a transformer model works, simply",
        "Write a haiku about the ocean",
        "Plan a relaxed 3-day trip to Lisbon",
        "Give me 5 dinner ideas with chickpeas",
    ]

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text(chat.supportsImages
                 ? "Ask anything, or attach a photo."
                 : "Ask anything. It all stays on your phone.")
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { text in
                    Button { suggest(text) } label: {
                        Text(text)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }
}

struct LoadingCard: View {
    let modelName: String
    let fraction: Double

    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: fraction) {
                Text(fraction < 1 ? "Downloading \(modelName)…" : "Loading \(modelName)…")
            } currentValueLabel: {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
            }
            if fraction < 1 {
                Label("You can lock your phone or leave the app. The download continues, and you'll get a notification when it's done.", systemImage: "moon.zzz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxHeight: .infinity)
    }
}
