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
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { AppBackground() }
                .safeAreaInset(edge: .bottom) { bottomBar }
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
                .padding(.horizontal, 6)
            }
            .buttonStyle(.glass)
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
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .padding()
        }
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inputBar: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                if let attachedImage {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: attachedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(.rect(cornerRadius: 14))
                        Button("Remove", systemImage: "xmark") { self.attachedImage = nil }
                            .labelStyle(.iconOnly)
                            .font(.caption.weight(.bold))
                            .frame(width: 24, height: 24)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .offset(x: 8, y: -8)
                    }
                    .padding(.leading, 54)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    photoButton

                    TextField("Ask anything", text: $input, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($inputFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))

                    if chat.isGenerating {
                        Button { chat.stop() } label: {
                            Image(systemName: "stop.fill")
                                .font(.headline)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel("Stop")
                    } else {
                        Button {
                            chat.send(input, image: attachedImage)
                            input = ""
                            attachedImage = nil
                            inputFocused = false
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(.brandPurple).interactive(), in: .circle)
                        .disabled(!canSend)
                        .opacity(canSend ? 1 : 0.5)
                        .accessibilityLabel("Send")
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var photoButton: some View {
        let icon = Image(systemName: "photo")
            .font(.title3)
            .frame(width: 44, height: 44)
        if chat.supportsImages {
            PhotosPicker(selection: $photoItem, matching: .images) { icon }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Attach photo")
        } else {
            Button { showImageHint = true } label: { icon.foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Attach photo")
        }
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
                    .glassEffect(.regular.tint(.brandPurple.opacity(0.85)), in: .rect(cornerRadius: 20))
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
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }
                if parts.answer.isEmpty && !parts.isThinking {
                    ProgressView()
                } else if !parts.answer.isEmpty {
                    Text(LocalizedStringKey(parts.answer))
                        .textSelection(.enabled)
                        .contextMenu { copyButton(parts.answer) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            BrandMark()
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
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
            }
            GlassEffectContainer(spacing: 12) {
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
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)

                    Button(action: openModels) {
                        Label("Choose another model", systemImage: "square.stack.3d.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                }
            }
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
        VStack(spacing: 24) {
            Spacer()
            BrandMark()
            Text(chat.supportsImages
                 ? "Ask anything, or attach a photo."
                 : "Ask anything. It all stays on your phone.")
                .foregroundStyle(.secondary)
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    ForEach(suggestions, id: \.self) { text in
                        Button { suggest(text) } label: {
                            Text(text)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.glass)
                    }
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
        VStack(spacing: 14) {
            ProgressView(value: fraction)
            HStack {
                Text(fraction < 1 ? "Downloading \(modelName)…" : "Loading \(modelName)…")
                Spacer()
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .font(.subheadline)
            if fraction < 1 {
                Label("You can lock your phone or leave the app. The download continues, and you'll get a notification when it's done.", systemImage: "moon.zzz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.horizontal, 32)
        .frame(maxHeight: .infinity)
    }
}

/// A glass disc with a sparkle, echoing the app icon.
struct BrandMark: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 40, weight: .semibold))
            .foregroundStyle(
                LinearGradient(colors: [.brandCyan, .brandPurple], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(width: 96, height: 96)
            .glassEffect(.regular, in: .circle)
    }
}
