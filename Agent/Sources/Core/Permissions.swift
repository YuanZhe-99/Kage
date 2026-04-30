import Foundation
import ApplicationServices
import AVFoundation

enum Permission {
    case screenCapture
    case accessibility

    var description: String {
        switch self {
        case .screenCapture:
            return "Screen Recording"
        case .accessibility:
            return "Accessibility"
        }
    }
}

class Permissions {
    static let shared = Permissions()

    private init() {}

    func checkScreenCapture() -> Bool {
        if #available(macOS 14.0, *) {
            return CGPreflightScreenCaptureAccess()
        } else {
            return CGDisplayStream(
                displayID: CGMainDisplayID(),
                outputWidth: 1,
                outputHeight: 1,
                pixelFormat: Int32(kCVPixelFormatType_32BGRA),
                properties: nil,
                handler: { _, _, _, _ in }
            ) != nil
        }
    }

    func requestScreenCapture() {
        if #available(macOS 14.0, *) {
            CGRequestScreenCaptureAccess()
        } else {
            let alert = NSAlert()
            alert.messageText = "Screen Recording Permission Required"
            alert.informativeText = "Kage needs screen recording permission to capture your screen. Please enable it in System Settings > Privacy & Security > Screen Recording."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                openScreenCaptureSettings()
            }
        }
    }

    func checkAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func checkAllPermissions() -> [Permission: Bool] {
        return [
            .screenCapture: checkScreenCapture(),
            .accessibility: checkAccessibility()
        ]
    }

    func requestAllPermissions() {
        if !checkScreenCapture() {
            requestScreenCapture()
        }

        if !checkAccessibility() {
            requestAccessibility()
        }
    }

    private func openScreenCaptureSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
