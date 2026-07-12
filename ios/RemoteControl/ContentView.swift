import SwiftUI

struct ContentView: View {
    @State private var manager = WebSocketManager()
    @AppStorage("tailscaleIP") private var host = ""
    @AppStorage("selectedOllamaModel") private var selectedModel = ""

    var body: some View {
        TabView {
            DashboardView(manager: manager, host: $host)
                .tabItem { Label("My Mac", systemImage: "laptopcomputer") }

            ModelsView(manager: manager, selectedModel: $selectedModel)
                .tabItem { Label("Models", systemImage: "cpu") }

            ChatView(manager: manager, selectedModel: selectedModel)
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
        }
    }
}
