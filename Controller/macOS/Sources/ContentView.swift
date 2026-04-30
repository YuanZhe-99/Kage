import SwiftUI

struct ContentView: View {
    @State private var isConnected = false
    @State private var showConnectionSheet = false
    @StateObject private var connectionManager = ConnectionManager()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left")
                }
            }

            ToolbarItem(placement: .principal) {
                connectionStatus
            }

            ToolbarItem(placement: .automatic) {
                Button(action: { showConnectionSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showConnectionSheet) {
            ConnectionSheet(isPresented: $showConnectionSheet, connectionManager: connectionManager)
        }
    }

    private var sidebar: some View {
        List {
            Section("Connections") {
                ForEach(connectionManager.savedConnections) { connection in
                    ConnectionRow(connection: connection)
                        .onTapGesture {
                            connectionManager.connect(to: connection)
                        }
                }
            }

            Section("Recent") {
                ForEach(connectionManager.recentConnections) { connection in
                    ConnectionRow(connection: connection)
                        .onTapGesture {
                            connectionManager.connect(to: connection)
                        }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var detail: some View {
        Group {
            if let activeConnection = connectionManager.activeConnection {
                RemoteDesktopView(connection: activeConnection)
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Remote Connection")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Click + to connect to a remote device")
                .font(.body)
                .foregroundColor(.secondary)

            Button("Connect") {
                showConnectionSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var connectionStatus: some View {
        HStack {
            Circle()
                .fill(connectionManager.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(connectionManager.isConnected ? "Connected" : "Disconnected")
                .font(.caption)
        }
    }

    private func toggleSidebar() {
        NSApp.keyWindow?.contentViewController?.tryToPerform(
            #selector(NSSplitViewController.toggleSidebar(_:)),
            with: nil
        )
    }
}

struct ConnectionRow: View {
    let connection: ConnectionInfo

    var body: some View {
        HStack {
            Image(systemName: connection.isOnline ? "desktopcomputer" : "desktopcomputer.trianglebadge.exclamationmark")
                .foregroundColor(connection.isOnline ? .green : .red)

            VStack(alignment: .leading) {
                Text(connection.name)
                    .font(.headline)
                Text(connection.uuid)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if connection.isOnline {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ConnectionSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var connectionManager: ConnectionManager

    @State private var deviceUUID = ""
    @State private var psk = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Connect to Remote Device")
                .font(.title2)

            Form {
                Section("Device Information") {
                    TextField("Device UUID", text: $deviceUUID)
                    SecureField("Pre-Shared Key", text: $psk)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Connect") {
                    connectionManager.connectToDevice(uuid: deviceUUID, psk: psk)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(deviceUUID.isEmpty || psk.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

class ConnectionManager: ObservableObject {
    @Published var savedConnections: [ConnectionInfo] = []
    @Published var recentConnections: [ConnectionInfo] = []
    @Published var activeConnection: ConnectionInfo?
    @Published var isConnected = false

    func connect(to connection: ConnectionInfo) {
        activeConnection = connection
        isConnected = true
    }

    func connectToDevice(uuid: String, psk: String) {
        let connection = ConnectionInfo(
            id: UUID(),
            name: "Device \(uuid.prefix(8))",
            uuid: uuid,
            psk: psk,
            isOnline: true
        )
        savedConnections.append(connection)
        connect(to: connection)
    }

    func disconnect() {
        activeConnection = nil
        isConnected = false
    }
}

struct ConnectionInfo: Identifiable {
    let id: UUID
    let name: String
    let uuid: String
    let psk: String
    let isOnline: Bool
}
