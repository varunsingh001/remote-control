import Foundation

struct ServerRequest: Encodable {
    let action: String
    var command: String?
    var model: String?
    var messages: [ChatMessagePayload]?
    var think: Bool?
    var temperature: Double?
    var source: String?
}

struct ChatMessagePayload: Codable {
    let role: String
    let content: String
}

struct ServerResponse: Decodable {
    let success: Bool
    var data: String?
    var error: String?
    var action: String?
    var done: Bool?
    var thinking: Bool?
}

struct DashboardData: Decodable {
    var hostname: String?
    var os: String?
    var arch: String?
    var processor: String?
    var cpu_cores: String?
    var memory_total: String?
    var battery: String?
    var disk: String?
    var uptime: String?
}

struct OllamaModel: Decodable, Identifiable {
    let name: String
    let size: Int64
    let modified_at: String?
    let family: String?
    let parameter_size: String?
    let quantization: String?
    let source: String?

    var id: String { name }
    var isMLX: Bool { source == "mlx" }

    var formattedSize: String {
        let gb = Double(size) / (1024 * 1024 * 1024)
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(size) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String
    var content: String
    var thinking: String?
}
