import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp: Date
}

enum MessageRole {
    case user
    case assistant
}

struct ChatWindowView: View {
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var selectedModel: String = "gpt-4o"

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            messageListView
            Divider()
            inputView
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var headerView: some View {
        HStack {
            Picker("Model", selection: $selectedModel) {
                Text("GPT-4o").tag("gpt-4o")
                Text("Claude 3.5").tag("claude-3.5-sonnet")
                Text("Local").tag("local")
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Spacer()

            Button(action: {
                NSApp.keyWindow?.close()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _ in
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputView: some View {
        HStack(spacing: 12) {
            TextField("Ask me anything...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit {
                    sendMessage()
                }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(inputText.isEmpty ? .gray : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || isLoading)
        }
        .padding()
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text, timestamp: Date())
        messages.append(userMessage)
        inputText = ""
        isLoading = true

        Task {
            await simulateResponse(for: text)
            isLoading = false
        }
    }

    private func simulateResponse(for query: String) async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let response = ChatMessage(
            role: .assistant,
            content: "I'm a simulated response. In production, this would call the \(selectedModel) API.",
            timestamp: Date()
        )

        await MainActor.run {
            messages.append(response)
        }
    }
}

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading) {
                Text(message.content)
                    .padding(12)
                    .background(message.role == .user ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(16)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if message.role == .assistant {
                Spacer()
            }
        }
    }
}

#Preview {
    ChatWindowView()
        .frame(width: 400, height: 600)
}
