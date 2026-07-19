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
                        Text("No Ollama or MLX models found.\nPull Ollama models or download MLX models from HuggingFace.")
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
            .navigationTitle("Models")
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
            Section {
                Toggle(isOn: $thinking) {
                    Label("Thinking", systemImage: "brain.head.profile")
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Temperature", systemImage: "thermometer.medium")
                        Spacer()
                        Text(String(format: "%.1f", temperature))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $temperature, in: 0...2, step: 0.1)
                        .tint(.orange)
                }
            } header: {
                Text("Settings")
            } footer: {
                Text("Thinking enables chain-of-thought reasoning. Higher temperature increases creativity.")
            }

            modelSection(
                title: "Ollama",
                models: manager.ollamaModels.filter { !$0.isMLX }
            )
            modelSection(
                title: "MLX",
                models: manager.ollamaModels.filter { $0.isMLX }
            )
        }
    }

    @ViewBuilder
    private func modelSection(title: String, models: [OllamaModel]) -> some View {
        if !models.isEmpty {
            Section(title) {
                ForEach(models) { model in
                    let isSelected = selectedModel == model.name
                    Button {
                        let previousModel = selectedModel
                        selectedModel = model.name
                        if previousModel != model.name, !previousModel.isEmpty {
                            let prevSource = manager.ollamaModels.first(where: { $0.name == previousModel })?.source ?? "ollama"
                            Task { await manager.unloadModel(name: previousModel, source: prevSource) }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isSelected ? "cpu.fill" : "cpu")
                                .font(.title2)
                                .foregroundStyle(isSelected ? .blue : .secondary)
                                .frame(width: 36)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.name)
                                    .font(.headline)
                                HStack(spacing: 6) {
                                    if let family = model.family, !family.isEmpty {
                                        ModelTag(family, icon: "brain")
                                    }
                                    if let paramSize = model.parameter_size, !paramSize.isEmpty {
                                        ModelTag(paramSize, icon: "number")
                                    }
                                    ModelTag(model.formattedSize, icon: "internaldrive")
                                }
                                if let quant = model.quantization, !quant.isEmpty {
                                    Text(quant)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                                    .font(.title3)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .tint(.primary)
                    .listRowBackground(
                        isSelected
                            ? Color.blue.opacity(0.08)
                            : Color.clear
                    )
                }
            }
        }
    }
}

private struct ModelTag: View {
    let text: String
    let icon: String

    init(_ text: String, icon: String) {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.fill.tertiary, in: Capsule())
    }
}
