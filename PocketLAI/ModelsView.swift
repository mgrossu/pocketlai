import SwiftUI

/// Pick, download and delete models. Shows which are already on the phone.
struct ModelsView: View {
    @Environment(ChatModel.self) private var chat
    @Environment(\.dismiss) private var dismiss
    @State private var customRepoID = ""
    @State private var pendingDelete: LMModel?
    @State private var confirmDeleteAll = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            List {
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
                    HStack {
                        TextField("mlx-community/model-name", text: $customRepoID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.callout.monospaced())
                            .focused($fieldFocused)
                            .submitLabel(.done)
                            .onSubmit { addCustomModel() }
                        Button("Add") { addCustomModel() }
                        .buttonStyle(.bordered)
                        .disabled(!customRepoID.contains("/"))
                    }
                } header: {
                    Text("Any Hugging Face model")
                } footer: {
                    Text("Paste the repo ID of any MLX model from huggingface.co/mlx-community. Its architecture must be supported by mlx-swift-lm.")
                }

                Section {
                    LabeledContent("Downloaded models", value: totalDownloaded)
                    Button("Delete all downloaded models", role: .destructive) {
                        confirmDeleteAll = true
                    }
                    .disabled(chat.downloadedSizes.isEmpty)
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Swipe a downloaded model to delete it. 👁 = understands photos. Sizes are about the memory a model needs; up to ~3 GB runs smoothly on iPhone 17 Pro.")
                }
            }
            // Scrolling hides the keyboard.
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { chat.refreshDownloads() }
            .confirmationDialog(
                "Delete \(pendingDelete?.name ?? "model")?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let pendingDelete { chat.deleteDownload(of: pendingDelete) }
                }
            } message: {
                Text("This frees \(sizeText(pendingDelete)). It downloads again the next time you load it.")
            }
            .confirmationDialog(
                "Delete all downloaded models?", isPresented: $confirmDeleteAll, titleVisibility: .visible
            ) {
                Button("Delete all (\(totalDownloaded))", role: .destructive) {
                    for model in ModelCatalog.builtIn + chat.customModels where chat.isDownloaded(model) {
                        chat.deleteDownload(of: model)
                    }
                }
            }
        }
    }

    private func row(for model: LMModel) -> some View {
        Button {
            dismiss()
            Task { await chat.load(model) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name).foregroundStyle(.primary)
                    Text(model.isCustom ? model.repoID : model.size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                status(for: model)
            }
        }
        .swipeActions {
            if chat.isDownloaded(model) {
                Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = model }
            }
            if model.isCustom {
                Button("Remove", systemImage: "minus.circle") { chat.removeCustomModel(model) }
            }
        }
    }

    @ViewBuilder
    private func status(for model: LMModel) -> some View {
        if chat.loadedModel == model {
            Label("Loaded", systemImage: "bolt.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
        } else if case .loading = chat.loadState, chat.selectedModel == model {
            ProgressView()
        } else if let size = chat.downloadedSizes[model.repoID] {
            Label(size.formatted(.byteCount(style: .file)), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Not downloaded")
        }
    }

    private func addCustomModel() {
        if customRepoID.contains("/") { chat.addCustomModel(customRepoID) }
        customRepoID = ""
        fieldFocused = false
    }

    private var totalDownloaded: String {
        chat.downloadedSizes.values.reduce(0, +).formatted(.byteCount(style: .file))
    }

    private func sizeText(_ model: LMModel?) -> String {
        guard let model, let size = chat.downloadedSizes[model.repoID] else { return "its storage" }
        return size.formatted(.byteCount(style: .file))
    }
}
