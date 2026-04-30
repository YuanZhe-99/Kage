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
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            event?.keyboardSetUnicodeString(string: string, length: 1)
            event?.post(tap: .cghidEventTap)

            let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            eventUp?.keyboardSetUnicodeString(string: string, length: 1)
            eventUp?.post(tap: .cghidEventTap)

            usleep(10000)
        }
    }

    func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        eventDown?.flags = modifiers
        eventDown?.post(tap: .cghidEventTap)

        let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        eventUp?.flags = modifiers
        eventUp?.post(tap: .cghidEventTap)
    }

    func scroll(at point: CGPoint, deltaX: Int32, deltaY: Int32) {
        let event = CGEvent(
            scrollEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        )
        event?.post(tap: .cghidEventTap)
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
