import SwiftUI

@main
struct ContextHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.window)

        WindowGroup {
            ChatWindowView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 400, height: 600)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
