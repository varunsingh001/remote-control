import SwiftUI

struct DashboardView: View {
    var manager: WebSocketManager
    @Binding var host: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    connectionSection

                    if manager.isConnected {
                        if manager.isLoadingDashboard {
                            ProgressView("Loading system info...")
                                .padding()
                        }

                        if let data = manager.dashboardData {
                            dashboardCards(data)
                        }

                        commandSection
                        outputSection
                    }
                }
                .padding()
            }
            .navigationTitle("My Mac")
            .toolbar {
                if manager.isConnected {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await manager.fetchDashboard() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable {
                if manager.isConnected {
                    await manager.fetchDashboard()
                }
            }
            .onChange(of: manager.isConnected) {
                if manager.isConnected {
                    Task { await manager.fetchDashboard() }
                }
            }
            .onAppear {
                if !host.isEmpty && !manager.isConnected && !manager.isConnecting {
                    manager.connect(to: host)
                }
            }
        }
    }

    private var connectionSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .foregroundStyle(.secondary)
                    TextField("Tailscale IP (e.g. 100.x.x.x)", text: $host)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.decimalPad)
                        .disabled(manager.isConnecting)
                }
                .padding(10)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))

                Button {
                    if manager.isConnected {
                        manager.disconnect()
                    } else if !manager.isConnecting {
                        manager.connect(to: host)
                    }
                } label: {
                    Group {
                        if manager.isConnecting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: manager.isConnected ? "xmark" : "bolt.fill")
                        }
                    }
                    .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderedProminent)
                .tint(manager.isConnected ? .red : manager.isConnecting ? .orange : .green)
                .disabled(manager.isConnecting)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(manager.isConnecting ? .orange : manager.isConnected ? .green : Color(.systemGray4))
                    .frame(width: 8, height: 8)
                    .overlay {
                        if manager.isConnecting {
                            Circle()
                                .stroke(.orange.opacity(0.4), lineWidth: 2)
                                .frame(width: 14, height: 14)
                        }
                    }
                Text(manager.isConnecting ? "Connecting..." : manager.isConnected ? "Connected" : "Not connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func dashboardCards(_ data: DashboardData) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
            InfoCard(title: "Hostname", value: data.hostname ?? "–", icon: "desktopcomputer", tint: .blue)
            InfoCard(title: "OS", value: data.os ?? "–", icon: "laptopcomputer", tint: .indigo)
            InfoCard(title: "Architecture", value: data.arch ?? "–", icon: "cpu", tint: .purple)
            InfoCard(title: "Processor", value: data.processor ?? "–", icon: "bolt.fill", tint: .orange)
            InfoCard(title: "CPU Cores", value: data.cpu_cores ?? "–", icon: "square.grid.2x2", tint: .teal)
            InfoCard(title: "Memory", value: data.memory_total ?? "–", icon: "memorychip", tint: .cyan)
            InfoCard(title: "Battery", value: data.battery ?? "–", icon: "battery.100", tint: .green)
            InfoCard(title: "Disk", value: data.disk ?? "–", icon: "internaldrive", tint: .pink)
            InfoCard(title: "Uptime", value: data.uptime ?? "–", icon: "clock", tint: .mint)
        }
    }

    private var commandSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Commands")
                .font(.headline)
                .padding(.top, 4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                CommandButton("System", icon: "desktopcomputer", tint: .blue) {
                    Task { await manager.systemInfo() }
                }
                CommandButton("Battery", icon: "battery.100", tint: .green) {
                    Task { await manager.runCommand("battery") }
                }
                CommandButton("Disk", icon: "internaldrive", tint: .pink) {
                    Task { await manager.runCommand("disk_space") }
                }
                CommandButton("Uptime", icon: "clock", tint: .mint) {
                    Task { await manager.runCommand("uptime") }
                }
                CommandButton("Memory", icon: "memorychip", tint: .cyan) {
                    Task { await manager.runCommand("memory") }
                }
                CommandButton("Network", icon: "network", tint: .orange) {
                    Task { await manager.runCommand("network") }
                }
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Output", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                if !manager.lastResponse.isEmpty {
                    Button {
                        UIPasteboard.general.string = manager.lastResponse
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            ScrollView {
                Text(manager.lastResponse.isEmpty ? "Run a command to see output here." : manager.lastResponse)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(manager.lastResponse.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 80, maxHeight: 200)
            .padding(12)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct InfoCard: View {
    let title: String
    let value: String
    let icon: String
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.footnote, design: .monospaced))
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct CommandButton: View {
    let title: String
    let icon: String
    var tint: Color = .accentColor
    let action: () -> Void

    init(_ title: String, icon: String, tint: Color = .accentColor, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
