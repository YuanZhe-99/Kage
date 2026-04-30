import SwiftUI

struct MenuBarView: View {
    @State private var recentChats: [String] = [
        "How to optimize Swift performance?",
        "Explain async/await in Swift",
        "Best practices for SwiftUI"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerSection
            Divider()
            recentChatsSection
            Divider()
            actionButtonsSection
        }
        .frame(width: 280)
        .padding(12)
    }

    private var headerSection: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundColor(.accentColor)

            Text("ContextHelper")
                .font(.headline)

            Spacer()

            Text("v1.0.0")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var recentChatsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(recentChats, id: \.self) { chat in
                Button(action: {
                    openChat(with: chat)
                }) {
                    Text(chat)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 6) {
            Button(action: openChatWindow) {
                Label("New Chat", systemImage: "plus.message")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            HStack {
                Button(action: openSettings) {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: quitApp) {
                    Label("Quit", systemImage: "power")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func openChatWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "ContextHelper" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func openChat(with text: String) {
        openChatWindow()
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func quitApp() {
        NSApp.terminate(nil)
    }
}

#Preview {
    MenuBarView()
}
