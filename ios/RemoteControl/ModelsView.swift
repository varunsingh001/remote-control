import SwiftUI

struct ModelsView: View {
    var manager: WebSocketManager
    @Binding var selectedModel: String
    @AppStorage("ollamaThinking") private var thinking = false
    @AppStorage("ollamaTemperature") private var temperature = 0.7

    var body: some View {
        NavigationStack {
            Group {
                if !manager.isConnected {
                    ContentUnavailableView(
                        "Not Connected",
                        systemImage: "wifi.slash",
                        description: Text("Connect to your Mac in the Dashboard tab.")
                    )
                } else if manager.isLoadingModels {
                    ProgressView("Fetching models...")
                } else if let error = manager.ollamaError {
                    ContentUnavailableView {
                        Label("Connection Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await manager.fetchOllamaModels() }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if manager.ollamaModels.isEmpty {
                    ContentUnavailableView {
                        Label("No Models Found", systemImage: "cpu")
                    } description: {
                        Text("Make sure Ollama is running on your Mac.\nPull models with: ollama pull <model>")
                    } actions: {
                        Button("Retry") {
                            Task { await manager.fetchOllamaModels() }
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    modelListWithSettings
                }
            }
            .navigationTitle("Ollama Models")
            .toolbar {
                if manager.isConnected {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await manager.fetchOllamaModels() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .onAppear {
                if manager.isConnected && manager.ollamaModels.isEmpty && manager.ollamaError == nil {
                    Task { await manager.fetchOllamaModels() }
                }
            }
        }
    }

    private var modelListWithSettings: some View {
        List {
            Section("Settings") {
                Toggle("Thinking", isOn: $thinking)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.1f", temperature))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $temperature, in: 0...2, step: 0.1)
                }
            }

            Section("Models") {
                ForEach(manager.ollamaModels) { model in
                    Button {
                        selectedModel = model.name
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.name)
                                    .font(.headline)
                                HStack(spacing: 8) {
                                    if let family = model.family, !family.isEmpty {
                                        Label(family, systemImage: "brain")
                                    }
                                    if let paramSize = model.parameter_size, !paramSize.isEmpty {
                                        Label(paramSize, systemImage: "number")
                                    }
                                    Label(model.formattedSize, systemImage: "internaldrive")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if let quant = model.quantization, !quant.isEmpty {
                                    Text("Quantization: \(quant)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            if selectedModel == model.name {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                                    .font(.title3)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
        }
    }
}
