import Foundation

@Observable
@MainActor
final class WebSocketManager {
    var isConnected = false
    var isConnecting = false
    var lastResponse = ""

    var dashboardData: DashboardData?
    var isLoadingDashboard = false

    var ollamaModels: [OllamaModel] = []
    var ollamaError: String?
    var isLoadingModels = false

    var chatMessages: [ChatMessage] = []
    var streamingResponse = ""
    var streamingThinking = ""
    var isStreaming = false
    var isToolRunning = false

    private var webSocket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var pendingContent = ""
    private var pendingThinking = ""
    private var flushTask: Task<Void, Never>?
    private var streamingTimeoutTask: Task<Void, Never>?

    func connect(to host: String, port: Int = 8765) {
        guard !host.isEmpty, let url = URL(string: "ws://\(host):\(port)") else {
            lastResponse = "Invalid host"
            return
        }

        disconnect()
        isConnecting = true
        isConnected = false

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        let session = URLSession(configuration: config)
        webSocket = session.webSocketTask(with: url)
        webSocket?.maximumMessageSize = 100 * 1024 * 1024
        webSocket?.resume()

        connectTask = Task {
            do {
                try await verifyConnection()
                guard !Task.isCancelled else { return }
                isConnected = true
                isConnecting = false
                receiveTask = Task { await receiveLoop() }
            } catch {
                guard !Task.isCancelled else { return }
                isConnecting = false
                isConnected = false
                webSocket?.cancel(with: .normalClosure, reason: nil)
                webSocket = nil
                lastResponse = "Connection failed: \(error.localizedDescription)"
            }
        }
    }

    func disconnect() {
        connectTask?.cancel()
        receiveTask?.cancel()
        streamingTimeoutTask?.cancel()
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        isConnected = false
        isConnecting = false
        isLoadingDashboard = false
        isLoadingModels = false
        isStreaming = false
        isToolRunning = false
        streamingResponse = ""
        dashboardData = nil
        ollamaModels = []
        ollamaError = nil
    }

    func fetchDashboard() async {
        isLoadingDashboard = true
        await send(ServerRequest(action: "dashboard"))
    }

    func fetchOllamaModels() async {
        isLoadingModels = true
        ollamaError = nil
        await send(ServerRequest(action: "ollama_list_models"))
    }

    func unloadModel(name: String, source: String) async {
        await send(ServerRequest(action: "unload_model", model: name, source: source))
    }

    func sendChatMessage(model: String, content: String, think: Bool, temperature: Double) async {
        if isStreaming {
            cancelStreaming()
        }

        let userMessage = ChatMessage(role: "user", content: content)
        chatMessages.append(userMessage)
        isStreaming = true
        isToolRunning = false
        streamingResponse = ""
        streamingThinking = ""

        let payloadMessages = chatMessages
            .filter { $0.role == "user" || $0.role == "assistant" }
            .map { ChatMessagePayload(role: $0.role, content: $0.content) }

        guard let data = try? JSONEncoder().encode(ServerRequest(
            action: "ollama_chat",
            model: model,
            messages: payloadMessages,
            think: think,
            temperature: temperature
        )),
        let string = String(data: data, encoding: .utf8) else {
            isStreaming = false
            return
        }
        do {
            try await webSocket?.send(.string(string))
            resetStreamingTimeout()
        } catch {
            isStreaming = false
        }
    }

    func cancelStreaming() {
        streamingTimeoutTask?.cancel()
        flushPending()
        if !streamingResponse.isEmpty || !streamingThinking.isEmpty {
            chatMessages.append(ChatMessage(role: "assistant", content: streamingResponse, thinking: streamingThinking.isEmpty ? nil : streamingThinking))
        }
        streamingResponse = ""
        streamingThinking = ""
        isStreaming = false
        isToolRunning = false
    }

    func clearChat() {
        chatMessages.removeAll()
        streamingResponse = ""
        streamingThinking = ""
        pendingContent = ""
        pendingThinking = ""
        isToolRunning = false
    }

    func systemInfo() async {
        await send(ServerRequest(action: "system_info"))
    }

    func runCommand(_ name: String) async {
        await send(ServerRequest(action: "run_command", command: name))
    }

    private func resetStreamingTimeout() {
        streamingTimeoutTask?.cancel()
        streamingTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled else { return }
            if isStreaming {
                cancelStreaming()
            }
        }
    }

    private func flushPending() {
        flushTask?.cancel()
        flushTask = nil
        if !pendingContent.isEmpty {
            streamingResponse += pendingContent
            pendingContent = ""
        }
        if !pendingThinking.isEmpty {
            streamingThinking += pendingThinking
            pendingThinking = ""
        }
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            flushPending()
        }
    }

    private func send(_ request: ServerRequest) async {
        guard let data = try? JSONEncoder().encode(request),
              let string = String(data: data, encoding: .utf8) else { return }
        try? await webSocket?.send(.string(string))
    }

    private func verifyConnection() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            webSocket?.sendPing { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }

    private nonisolated func receiveLoop() async {
        while !Task.isCancelled {
            do {
                guard let message = try await webSocket?.receive() else {
                    await MainActor.run {
                        if isConnected {
                            isConnected = false
                            isStreaming = false
                            isToolRunning = false
                            lastResponse = "Connection lost"
                        }
                    }
                    break
                }
                if case .string(let text) = message,
                   let data = text.data(using: .utf8),
                   let response = try? JSONDecoder().decode(ServerResponse.self, from: data) {
                    await MainActor.run {
                        handleResponse(response)
                    }
                }
            } catch {
                await MainActor.run {
                    isConnected = false
                    isStreaming = false
                    isToolRunning = false
                    lastResponse = "Disconnected: \(error.localizedDescription)"
                }
                break
            }
        }
    }

    private func handleResponse(_ response: ServerResponse) {
        resetStreamingTimeout()

        guard response.success else {
            let error = response.error ?? "Unknown error"
            if isStreaming {
                let errorContent = streamingResponse.isEmpty
                    ? "Error: \(error)"
                    : streamingResponse + "\n\n[Error: \(error)]"
                chatMessages.append(ChatMessage(role: "assistant", content: errorContent))
                streamingResponse = ""
                isStreaming = false
                isToolRunning = false
            }
            if isLoadingModels {
                ollamaError = error
                isLoadingModels = false
            }
            isLoadingDashboard = false
            lastResponse = "Error: \(error)"
            return
        }

        switch response.action {
        case "dashboard":
            isLoadingDashboard = false
            if let jsonStr = response.data,
               let jsonData = jsonStr.data(using: .utf8) {
                dashboardData = try? JSONDecoder().decode(DashboardData.self, from: jsonData)
            }
        case "ollama_list_models":
            isLoadingModels = false
            if let jsonStr = response.data,
               let jsonData = jsonStr.data(using: .utf8) {
                ollamaModels = (try? JSONDecoder().decode([OllamaModel].self, from: jsonData)) ?? []
            }
        case "ollama_chat":
            if let content = response.data, !content.isEmpty {
                if response.thinking == true {
                    pendingThinking += content
                } else {
                    pendingContent += content
                }
                scheduleFlush()
            }
            if response.done == true {
                streamingTimeoutTask?.cancel()
                flushPending()
                if !streamingResponse.isEmpty || !streamingThinking.isEmpty {
                    chatMessages.append(ChatMessage(role: "assistant", content: streamingResponse, thinking: streamingThinking.isEmpty ? nil : streamingThinking))
                }
                streamingResponse = ""
                streamingThinking = ""
                isStreaming = false
                isToolRunning = false
            }
        case "ollama_chat_tool":
            isToolRunning = true
            if let toolMsg = response.data {
                if response.done == true {
                    if let idx = chatMessages.lastIndex(where: { $0.role == "tool" }) {
                        if chatMessages[idx].content.hasPrefix("⏳") {
                            chatMessages.remove(at: idx)
                        } else {
                            let truncated = toolMsg.count > 80 ? String(toolMsg.prefix(80)) + "…" : toolMsg
                            chatMessages[idx].content += " → " + truncated
                        }
                    }
                    isToolRunning = false
                } else {
                    let lookupTools = ["list_running_apps", "get_top_processes", "get_clipboard"]
                    let isLookup = lookupTools.contains(where: { toolMsg.hasPrefix($0) })
                    if isLookup {
                        chatMessages.append(ChatMessage(role: "tool", content: "⏳ Checking…"))
                    } else {
                        chatMessages.append(ChatMessage(role: "tool", content: toolMsg))
                    }
                }
            }
        default:
            lastResponse = response.data ?? ""
        }
    }
}
