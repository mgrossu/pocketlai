import SwiftUI

struct SettingsView: View {
    @Environment(ChatModel.self) private var chat
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance: Appearance = .system
    @FocusState private var promptFocused: Bool

    var body: some View {
        @Bindable var chat = chat
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Thinking mode", isOn: $chat.thinkingEnabled)
                } footer: {
                    Text("For models that support it (e.g. Qwen3.5, DeepSeek R1): reason step by step before answering. Slower, but better on hard questions.")
                }

                Section {
                    TextField("System prompt", text: $chat.systemPrompt, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($promptFocused)
                } header: {
                    Text("System prompt")
                } footer: {
                    Text("Applies from your next message.")
                }

                Section("About") {
                    LabeledContent("Model in memory", value: chat.loadedModel?.name ?? "None")
                    LabeledContent(
                        "Free memory", value: chat.availableMemory.formatted(.byteCount(style: .memory)))
                    LabeledContent("Saved chats", value: "\(chat.conversations.count)")
                    Text("Pockli runs models on-device with MLX. Chats, photos and models never leave this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            // Scrolling hides the keyboard.
            .scrollDismissesKeyboard(.immediately)
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
