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
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message...", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 22))
                .onSubmit { sendMessage() }

            Button {
                if manager.isStreaming {
                    manager.cancelStreaming()
                } else {
                    sendMessage()
                }
            } label: {
                Image(systemName: manager.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        manager.isStreaming
                            ? .red
                            : input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color(.systemGray3)
                                : .blue
                    )
                    .symbolEffect(.pulse, isActive: manager.isStreaming)
            }
            .disabled(!manager.isStreaming && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
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
            if manager.streamingResponse.isEmpty && manager.streamingThinking.isEmpty {
                TypingIndicator()
            } else if manager.streamingResponse.isEmpty && !manager.streamingThinking.isEmpty {
                HStack {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Thinking...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 16))
                    Spacer(minLength: 40)
                }
            } else {
                ChatBubble(message: ChatMessage(role: "assistant", content: manager.streamingResponse))
            }
        }
    }
}

struct ToolCallBubble: View {
    let content: String

    private var isLoading: Bool { content.hasPrefix("\u{231B}") }

    var body: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.caption2)
            }
            Text(content)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 0) {
                if let thinking = message.thinking, !thinking.isEmpty {
                    ThinkingBlock(text: thinking)
                }
                Group {
                    if isUser {
                        Text(message.content)
                    } else {
                        MarkdownText(content: message.content)
                    }
                }
                .padding(12)
                .background(
                    isUser ? Color.blue : Color(.systemGray5),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .foregroundStyle(isUser ? .white : .primary)
            }
            .textSelection(.enabled)
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

struct ThinkingBlock: View {
    let text: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text("Thinking")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

struct MarkdownText: View {
    let content: String

    private enum Block {
        case paragraph(String)
        case codeBlock(language: String?, code: String)
        case heading(Int, String)
        case listItem(String)
        case numberedItem(String, String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: lang.isEmpty ? nil : lang, code: codeLines.joined(separator: "\n")))
                i += 1
                continue
            }

            if let match = line.wholeMatch(of: /^(#{1,3})\s+(.+)/) {
                blocks.append(.heading(match.1.count, String(match.2)))
                i += 1
                continue
            }

            if let match = line.wholeMatch(of: /^\s*[\-\*]\s+(.+)/) {
                blocks.append(.listItem(String(match.1)))
                i += 1
                continue
            }

            if let match = line.wholeMatch(of: /^\s*(\d+)\.\s+(.+)/) {
                blocks.append(.numberedItem(String(match.1), String(match.2)))
                i += 1
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            var paraLines = [line]
            i += 1
            while i < lines.count {
                let next = lines[i]
                if next.trimmingCharacters(in: .whitespaces).isEmpty
                    || next.hasPrefix("```") || next.hasPrefix("#")
                    || next.wholeMatch(of: /^\s*[\-\*]\s+.+/) != nil
                    || next.wholeMatch(of: /^\s*\d+\.\s+.+/) != nil
                {
                    break
                }
                paraLines.append(next)
                i += 1
            }
            blocks.append(.paragraph(paraLines.joined(separator: " ")))
        }

        return blocks
    }

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            inlineMarkdown(text)
        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 0) {
                if let language {
                    HStack {
                        Text(language)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = code
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                }
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGray4).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        case .heading(let level, let text):
            inlineMarkdown(text)
                .font(level == 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
        case .listItem(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("\u{2022}")
                inlineMarkdown(text)
            }
        case .numberedItem(let num, let text):
            HStack(alignment: .top, spacing: 6) {
                Text("\(num).")
                    .monospacedDigit()
                inlineMarkdown(text)
            }
        }
    }

    private func inlineMarkdown(_ string: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(string)
    }
}
