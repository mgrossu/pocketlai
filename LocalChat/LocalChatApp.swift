import SwiftUI

@main
struct LocalChatApp: App {
    @State private var chat = ChatModel()

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(chat)
        }
    }
}
