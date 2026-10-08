import SwiftUI

@main
struct PocketLLMApp: App {
    @State private var chat = ChatModel()

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(chat)
        }
    }
}
