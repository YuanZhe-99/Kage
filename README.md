# ContextHelper

A local AI assistant for macOS that provides a floating chat window and context-aware assistance.

## Features

- **Floating Chat Window**: Access AI assistance from anywhere with a global keyboard shortcut
- **Multiple AI Models**: Support for GPT-4o, Claude 3.5, and local models
- **Context Awareness**: Analyzes your current work context to provide relevant help
- **Menu Bar Integration**: Quick access from the menu bar without cluttering your dock
- **Privacy First**: All processing happens locally, your data stays on your device

## Installation

### Option 1: Download Release

Download the latest `.dmg` from the [Releases](../../releases) page and drag to Applications.

### Option 2: Build from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/ContextHelper.git
cd ContextHelper

# Build the agent
cd Agent
swift build -c release

# Run
.build/release/ContextHelper
```

## Usage

1. Launch ContextHelper from Applications or Spotlight
2. The app appears in your menu bar (sparkles icon)
3. Click the icon or press `Cmd+Shift+Space` to open the chat window
4. Type your question and get instant AI assistance

## Configuration

### API Keys

1. Open Settings (click gear icon in menu bar)
2. Enter your API key for your preferred AI provider
3. Optionally customize the API endpoint

### Keyboard Shortcuts

- `Cmd+Shift+Space`: Toggle chat window
- `Enter`: Send message
- `Shift+Enter`: New line

## Privacy

ContextHelper is designed with privacy in mind:

- No data is sent to external servers without your explicit consent
- API keys are stored securely in macOS Keychain
- Chat history is stored locally in `~/Library/Application Support/ContextHelper/`
- No analytics or tracking

## System Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel processor
- Internet connection (for cloud AI models)

## License

MIT License - See [LICENSE](LICENSE) for details

## Support

For issues and feature requests, please open an issue on GitHub.

---

**Note**: This is a local AI assistant application. All remote assistance features require explicit user configuration and consent.
