import Foundation
import AppKit

protocol InputCaptureDelegate: AnyObject {
    func inputCapture(_ capture: InputCapture, didCaptureMouseEvent event: MouseEvent)
    func inputCapture(_ capture: InputCapture, didCaptureKeyEvent event: KeyEvent)
}

class InputCapture {
    weak var delegate: InputCaptureDelegate?

    private var mouseMonitor: Any?
    private var keyboardMonitor: Any?
    private var isCapturing = false

    var screenSize: CGSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)

    func startCapturing() {
        guard !isCapturing else { return }
        isCapturing = true

        setupMouseMonitor()
        setupKeyboardMonitor()
    }

    func stopCapturing() {
        guard isCapturing else { return }
        isCapturing = false

        if let mouseMonitor = mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }

        if let keyboardMonitor = keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }

    private func setupMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]) { [weak self] event in
            self?.handleMouseEvent(event)
        }
    }

    private func setupKeyboardMonitor() {
        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            self?.handleKeyEvent(event)
        }
    }

    private func handleMouseEvent(_ event: NSEvent) {
        let location = event.locationInWindow
        let normalizedX = location.x / screenSize.width
        let normalizedY = location.y / screenSize.height

        var mouseEvent: MouseEvent

        switch event.type {
        case .mouseMoved:
            mouseEvent = MouseEvent(type: .move, x: normalizedX, y: normalizedY, button: .none, timestamp: event.timestamp)
        case .leftMouseDown:
            mouseEvent = MouseEvent(type: .buttonDown, x: normalizedX, y: normalizedY, button: .left, timestamp: event.timestamp)
        case .leftMouseUp:
            mouseEvent = MouseEvent(type: .buttonUp, x: normalizedX, y: normalizedY, button: .left, timestamp: event.timestamp)
        case .rightMouseDown:
            mouseEvent = MouseEvent(type: .buttonDown, x: normalizedX, y: normalizedY, button: .right, timestamp: event.timestamp)
        case .rightMouseUp:
            mouseEvent = MouseEvent(type: .buttonUp, x: normalizedX, y: normalizedY, button: .right, timestamp: event.timestamp)
        case .otherMouseDown:
            mouseEvent = MouseEvent(type: .buttonDown, x: normalizedX, y: normalizedY, button: .middle, timestamp: event.timestamp)
        case .otherMouseUp:
            mouseEvent = MouseEvent(type: .buttonUp, x: normalizedX, y: normalizedY, button: .middle, timestamp: event.timestamp)
        case .scrollWheel:
            mouseEvent = MouseEvent(type: .scroll, x: normalizedX, y: normalizedY, scrollX: event.deltaX, scrollY: event.deltaY, timestamp: event.timestamp)
        default:
            return
        }

        delegate?.inputCapture(self, didCaptureMouseEvent: mouseEvent)
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let keyEvent = KeyEvent(
            type: event.type == .keyDown ? .keyDown : .keyUp,
            keyCode: event.keyCode,
            characters: event.characters,
            modifiers: event.modifierFlags,
            timestamp: event.timestamp
        )

        delegate?.inputCapture(self, didCaptureKeyEvent: keyEvent)
    }
}

struct MouseEvent {
    let type: MouseEventType
    let x: CGFloat
    let y: CGFloat
    let button: MouseButton
    let scrollX: CGFloat
    let scrollY: CGFloat
    let timestamp: TimeInterval

    init(type: MouseEventType, x: CGFloat, y: CGFloat, button: MouseButton = .none, scrollX: CGFloat = 0, scrollY: CGFloat = 0, timestamp: TimeInterval) {
        self.type = type
        self.x = x
        self.y = y
        self.button = button
        self.scrollX = scrollX
        self.scrollY = scrollY
        self.timestamp = timestamp
    }

    enum MouseEventType {
        case move
        case buttonDown
        case buttonUp
        case scroll
    }

    enum MouseButton {
        case none
        case left
        case right
        case middle
    }
}

struct KeyEvent {
    let type: KeyEventType
    let keyCode: UInt16
    let characters: String?
    let modifiers: NSEvent.ModifierFlags
    let timestamp: TimeInterval

    enum KeyEventType {
        case keyDown
        case keyUp
    }
}
