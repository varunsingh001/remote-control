import Combine
import SwiftUI

struct ChatView: View {
    var manager: WebSocketManager
    let selectedModel: String
    @AppStorage("ollamaThinking") private var thinking = false
    @AppStorage("ollamaTemperature") private var temperature = 0.7
    @State private var input = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if !manager.isConnected {
                    ContentUnavailableView(
                        "Not Connected",
                        systemImage: "wifi.slash",
                        description: Text("Connect to your Mac in the Dashboard tab.")
                    )
                } else if selectedModel.isEmpty {
                    ContentUnavailableView(
                        "No Model Selected",
                        systemImage: "cpu",
                        description: Text("Select a model in the Models tab to start chatting.")
                    )
                } else {
                    chatContent
                }
            }
            .navigationTitle(selectedModel.isEmpty ? "Chat" : selectedModel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !manager.chatMessages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", role: .destructive) {
                            manager.clearChat()
                        }
                    }
                }
            }
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(manager.chatMessages) { message in
                            if message.role == "tool" {
                                ToolCallBubble(content: message.content)
                            } else {
                                ChatBubble(message: message)
                            }
                        }
                        StreamingSection(manager: manager)
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding()
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture { isInputFocused = false }
                .onChange(of: manager.chatMessages.count) {
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                    if manager.isStreaming {
                        proxy.scrollTo("bottom")
                    }
                }
            }

            Divider()
            inputBar
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message...", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(10)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 20))

            if manager.isStreaming {
                Button {
                    manager.cancelStreaming()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title)
                        .foregroundStyle(.red)
                }
            } else {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func sendMessage() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !manager.isStreaming else { return }
        input = ""
        Task { await manager.sendChatMessage(model: selectedModel, content: text, think: thinking, temperature: temperature) }
    }
}

struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(dotScale(for: index))
                        .opacity(dotOpacity(for: index))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 16))
            Spacer(minLength: 40)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                phase = 1.0
            }
        }
    }

    private func dotScale(for index: Int) -> CGFloat {
        let offset = Double(index) * 0.15
        let value = sin((phase + offset) * .pi)
        return 0.6 + 0.4 * value
    }

    private func dotOpacity(for index: Int) -> CGFloat {
        let offset = Double(index) * 0.15
        let value = sin((phase + offset) * .pi)
        return 0.4 + 0.6 * value
    }
}

struct StreamingSection: View {
    var manager: WebSocketManager

    var body: some View {
        if manager.isStreaming {
            if manager.streamingResponse.isEmpty {
                TypingIndicator()
            } else {
                ChatBubble(message: ChatMessage(role: "assistant", content: manager.streamingResponse))
            }
        }
    }
}

struct ToolCallBubble: View {
    let content: String

    var body: some View {
        Label(content, systemImage: "gearshape.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemGray6), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content)
                .padding(12)
                .background(
                    isUser ? Color.blue : Color(.systemGray5),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .foregroundStyle(isUser ? .white : .primary)
                .textSelection(.enabled)
            if !isUser { Spacer(minLength: 40) }
        }
    }
}
