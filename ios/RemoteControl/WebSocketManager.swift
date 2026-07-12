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
    var isStreaming = false

    private var webSocket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?

    func connect(to host: String, port: Int = 8765) {
        guard !host.isEmpty, let url = URL(string: "ws://\(host):\(port)") else {
            lastResponse = "Invalid host"
            return
        }

        disconnect()
        isConnecting = true
        isConnected = false

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)
        webSocket = session.webSocketTask(with: url)
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
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        isConnected = false
        isConnecting = false
        isLoadingDashboard = false
        isLoadingModels = false
        isStreaming = false
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

    func sendChatMessage(model: String, content: String, think: Bool, temperature: Double) async {
        let userMessage = ChatMessage(role: "user", content: content)
        chatMessages.append(userMessage)
        isStreaming = true
        streamingResponse = ""

        let payloadMessages = chatMessages
            .filter { $0.role == "user" || $0.role == "assistant" }
            .map { ChatMessagePayload(role: $0.role, content: $0.content) }
        await send(ServerRequest(
            action: "ollama_chat",
            model: model,
            messages: payloadMessages,
            think: think,
            temperature: temperature
        ))
    }

    func cancelStreaming() {
        if !streamingResponse.isEmpty {
            chatMessages.append(ChatMessage(role: "assistant", content: streamingResponse))
        }
        streamingResponse = ""
        isStreaming = false
    }

    func clearChat() {
        chatMessages.removeAll()
        streamingResponse = ""
    }

    func systemInfo() async {
        await send(ServerRequest(action: "system_info"))
    }

    func runCommand(_ name: String) async {
        await send(ServerRequest(action: "run_command", command: name))
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
                guard let message = try await webSocket?.receive() else { break }
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
                    lastResponse = "Disconnected: \(error.localizedDescription)"
                }
                break
            }
        }
    }

    private func handleResponse(_ response: ServerResponse) {
        guard response.success else {
            let error = response.error ?? "Unknown error"
            if isStreaming {
                let errorContent = streamingResponse.isEmpty
                    ? "Error: \(error)"
                    : streamingResponse + "\n\n[Error: \(error)]"
                chatMessages.append(ChatMessage(role: "assistant", content: errorContent))
                streamingResponse = ""
                isStreaming = false
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
                streamingResponse += content
            }
            if response.done == true {
                if !streamingResponse.isEmpty {
                    chatMessages.append(ChatMessage(role: "assistant", content: streamingResponse))
                }
                streamingResponse = ""
                isStreaming = false
            }
        case "ollama_chat_tool":
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
