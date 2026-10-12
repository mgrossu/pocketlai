import SwiftUI

@main
struct PocketLAIApp: App {
    @State private var chat = ChatModel()

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(chat)
        }
    }
}
