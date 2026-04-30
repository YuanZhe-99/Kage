import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var apiEndpoint: String = "https://api.openai.com/v1"
    @State private var showAdvanced: Bool = false
    @State private var remoteEnabled: Bool = false
    @State private var psk: String = ""
    @State private var deviceUUID: String = ""
    @State private var publicKey: String = ""

    var body: some View {
        TabView {
            GeneralSettingsView(apiKey: $apiKey, apiEndpoint: $apiEndpoint)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AdvancedSettingsView(showAdvanced: $showAdvanced)
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }

            RemoteSettingsView(
                remoteEnabled: $remoteEnabled,
                psk: $psk,
                deviceUUID: $deviceUUID,
                publicKey: $publicKey
            )
            .tabItem {
                Label("Remote", systemImage: "network")
            }
        }
        .frame(width: 450, height: 300)
        .onAppear {
            loadSettings()
        }
    }

    private func loadSettings() {
        deviceUUID = UserDefaults.standard.string(forKey: "deviceUUID") ?? "Not generated"
        publicKey = UserDefaults.standard.string(forKey: "publicKey") ?? "Not generated"
    }
}

struct GeneralSettingsView: View {
    @Binding var apiKey: String
    @Binding var apiEndpoint: String

    var body: some View {
        Form {
            Section("API Configuration") {
                SecureField("API Key", text: $apiKey)
                TextField("Endpoint", text: $apiEndpoint)
            }

            Section("Model") {
                Picker("Default Model", selection: .constant("gpt-4o")) {
                    Text("GPT-4o").tag("gpt-4o")
                    Text("GPT-4o Mini").tag("gpt-4o-mini")
                    Text("Claude 3.5 Sonnet").tag("claude-3.5-sonnet")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AdvancedSettingsView: View {
    @Binding var showAdvanced: Bool

    var body: some View {
        Form {
            Section("Performance") {
                Toggle("Enable hardware acceleration", isOn: .constant(true))
                Toggle("Limit frame rate to 30fps", isOn: .constant(false))
            }

            Section("Network") {
                Picker("Transport", selection: .constant("quic")) {
                    Text("QUIC (Recommended)").tag("quic")
                    Text("HTTP/2").tag("http2")
                    Text("Auto").tag("auto")
                }

                Toggle("Enable TURN relay fallback", isOn: .constant(true))
            }

            Section("Debug") {
                Toggle("Verbose logging", isOn: .constant(false))
                Toggle("Show network statistics", isOn: .constant(false))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct RemoteSettingsView: View {
    @Binding var remoteEnabled: Bool
    @Binding var psk: String
    @Binding var deviceUUID: String
    @Binding var publicKey: String

    var body: some View {
        Form {
            Section("Remote Access") {
                Toggle("Enable remote access", isOn: $remoteEnabled)

                if remoteEnabled {
                    SecureField("Pre-Shared Key", text: $psk)
                }
            }

            Section("Device Identity") {
                LabeledContent("UUID", value: deviceUUID)
                LabeledContent("Public Key", value: publicKey)

                Button("Regenerate Identity") {
                    regenerateIdentity()
                }
                .foregroundColor(.red)
            }

            Section("Status") {
                LabeledContent("Connection", value: "Not connected")
                LabeledContent("Last seen", value: "Never")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func regenerateIdentity() {
        // TODO: Implement identity regeneration
    }
}

#Preview {
    SettingsView()
}
