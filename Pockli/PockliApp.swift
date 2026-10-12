import SwiftUI

@main
struct PockliApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var chat = ChatModel()
    @AppStorage("appearance") private var appearance: Appearance = .system
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(chat)
                .tint(.brandPurple)
                .preferredColorScheme(appearance.colorScheme)
                .onChange(of: scenePhase) {
                    if scenePhase == .background { chat.didEnterBackground() }
                }
        }
    }
}
