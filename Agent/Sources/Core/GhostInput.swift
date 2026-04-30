import Foundation
import ApplicationServices
import CoreGraphics

class GhostInput {
    private let systemWide = AXUIElementCreateSystemWide()

    func click(at point: CGPoint, button: MouseButton = .left) {
        guard let element = getElementAtPosition(point) else { return }

        switch button {
        case .left:
            performAction(kAXPressAction, on: element)
        case .right:
            performAction(kAXShowMenuAction, on: element)
        case .middle:
            performAction(kAXPressAction, on: element)
        }
    }

    func doubleClick(at point: CGPoint) {
        guard let element = getElementAtPosition(point) else { return }
        AXUIElementPerformAction(element, kAXPressAction as CFString)
        usleep(50000)
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    func focusElement(at point: CGPoint) {
        guard let element = getElementAtPosition(point) else { return }
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    func typeText(_ text: String) {
        for char in text {
            let string = String(char)
            var unichar = Array(string.utf16)
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
            event?.post(tap: CGEventTapLocation.cghidEventTap)

            let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            eventUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
            eventUp?.post(tap: CGEventTapLocation.cghidEventTap)

            usleep(10000)
        }
    }

    func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        eventDown?.flags = modifiers
        eventDown?.post(tap: CGEventTapLocation.cghidEventTap)

        let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        eventUp?.flags = modifiers
        eventUp?.post(tap: CGEventTapLocation.cghidEventTap)
    }

    func scroll(at point: CGPoint, deltaX: Int32, deltaY: Int32) {
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        )
        event?.post(tap: CGEventTapLocation.cghidEventTap)
    }

    private func getElementAtPosition(_ point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &element
        )

        return result == .success ? element : nil
    }

    private func performAction(_ action: String, on element: AXUIElement) {
        AXUIElementPerformAction(element, action as CFString)
    }

    func getValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    func setValue(_ value: String, for element: AXUIElement) -> Bool {
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef)
        return result == .success
    }

    func getTitle(of element: AXUIElement) -> String? {
        var title: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        guard result == .success else { return nil }
        return title as? String
    }

    func getRole(of element: AXUIElement) -> String? {
        var role: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        guard result == .success else { return nil }
        return role as? String
    }
}

enum MouseButton {
    case left
    case right
    case middle
}
