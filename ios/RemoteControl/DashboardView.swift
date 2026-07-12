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
        VStack(spacing: 8) {
            HStack {
                TextField("Tailscale IP (e.g. 100.x.x.x)", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.decimalPad)
                    .disabled(manager.isConnecting)

                Button {
                    if manager.isConnected {
                        manager.disconnect()
                    } else if !manager.isConnecting {
                        manager.connect(to: host)
                    }
                } label: {
                    if manager.isConnecting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                            Text("Connecting")
                        }
                    } else {
                        Text(manager.isConnected ? "Disconnect" : "Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(manager.isConnected ? .red : manager.isConnecting ? .orange : .green)
                .disabled(manager.isConnecting)
            }

            HStack {
                if manager.isConnecting {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Circle()
                        .fill(manager.isConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                }
                Text(manager.isConnecting ? "Connecting..." : manager.isConnected ? "Connected" : "Disconnected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func dashboardCards(_ data: DashboardData) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
            InfoCard(title: "Hostname", value: data.hostname ?? "–", icon: "desktopcomputer")
            InfoCard(title: "OS", value: data.os ?? "–", icon: "laptopcomputer")
            InfoCard(title: "Architecture", value: data.arch ?? "–", icon: "cpu")
            InfoCard(title: "Processor", value: data.processor ?? "–", icon: "bolt")
            InfoCard(title: "CPU Cores", value: data.cpu_cores ?? "–", icon: "square.grid.2x2")
            InfoCard(title: "Memory", value: data.memory_total ?? "–", icon: "memorychip")
            InfoCard(title: "Battery", value: data.battery ?? "–", icon: "battery.100")
            InfoCard(title: "Disk", value: data.disk ?? "–", icon: "internaldrive")
            InfoCard(title: "Uptime", value: data.uptime ?? "–", icon: "clock")
        }
    }

    private var commandSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Commands")
                .font(.headline)
                .padding(.top, 4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
                CommandButton("System Info", icon: "desktopcomputer") {
                    Task { await manager.systemInfo() }
                }
                CommandButton("Battery", icon: "battery.100") {
                    Task { await manager.runCommand("battery") }
                }
                CommandButton("Disk Space", icon: "internaldrive") {
                    Task { await manager.runCommand("disk_space") }
                }
                CommandButton("Uptime", icon: "clock") {
                    Task { await manager.runCommand("uptime") }
                }
                CommandButton("Memory", icon: "memorychip") {
                    Task { await manager.runCommand("memory") }
                }
                CommandButton("Network", icon: "network") {
                    Task { await manager.runCommand("network") }
                }
            }
        }
    }

    private var outputSection: some View {
        GroupBox("Output") {
            ScrollView {
                Text(manager.lastResponse.isEmpty ? "No output yet" : manager.lastResponse)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 100, maxHeight: 200)
        }
    }
}

struct InfoCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct CommandButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    init(_ title: String, icon: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
