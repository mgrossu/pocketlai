import SwiftUI

@main
struct PocketLAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var chat = ChatModel()
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(chat)
                .tint(.brandPurple)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
