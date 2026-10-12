import SwiftUI

/// Saved chats. Opening one restores its text as the model's context.
struct HistoryView: View {
    @Environment(ChatModel.self) private var chat
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var confirmDeleteAll = false

    private var results: [Conversation] {
        guard !search.isEmpty else { return chat.conversations }
        return chat.conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(search)
                || conversation.messages.contains { $0.text.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { conversation in
                    Button {
                        chat.open(conversation)
                        dismiss()
                    } label: {
                        row(for: conversation)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            chat.delete(conversation)
                        }
                    }
                }
            }
            .overlay {
                if chat.conversations.isEmpty {
                    ContentUnavailableView(
                        "No chats yet", systemImage: "bubble.left.and.bubble.right",
                        description: Text("Your conversations are saved here, on this iPhone only."))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Search chats")
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Delete all", systemImage: "trash", role: .destructive) {
                        confirmDeleteAll = true
                    }
                    .disabled(chat.conversations.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New chat", systemImage: "square.and.pencil") {
                        chat.newChat()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete all chats?", isPresented: $confirmDeleteAll, titleVisibility: .visible
            ) {
                Button("Delete all", role: .destructive) { chat.deleteAllChats() }
            } message: {
                Text("This removes every saved conversation and its photos.")
            }
        }
    }

    private func row(for conversation: Conversation) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle(for: conversation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if conversation.id == chat.conversation.id {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
    }

    private func subtitle(for conversation: Conversation) -> String {
        let date = conversation.updatedAt.formatted(.relative(presentation: .named))
        let photos = conversation.messages.filter { $0.imageFile != nil }.count
        return [
            conversation.modelName,
            date,
            photos > 0 ? "\(photos) photo\(photos == 1 ? "" : "s")" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
