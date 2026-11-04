//
//  WindowActivator.swift
//  eve-operator
//
//  Brings an individual EVE window to the foreground via the Accessibility API.
//

import AppKit
import ApplicationServices

enum WindowActivator {

    enum ActivationError: LocalizedError {
        case processGone
        case accessibilityDenied
        case windowNotFound
        case raiseFailed(AXError)

        var errorDescription: String? {
            switch self {
            case .processGone:
                return "That EVE client is no longer running."
            case .accessibilityDenied:
                return "eve-operator needs Accessibility permission to raise windows."
            case .windowNotFound:
                return "Activated the client, but couldn't find that exact window."
            case .raiseFailed(let error):
                return "Raising the window failed (AXError \(error.rawValue))."
            }
        }
    }

    static func bringToFront(_ window: EVEWindow) throws {
        guard let app = NSRunningApplication(processIdentifier: window.processIdentifier) else {
            throw ActivationError.processGone
        }
        guard AccessibilityPermission.isGranted else {
            throw ActivationError.accessibilityDenied
        }

        guard let element = accessibilityWindow(matching: window) else {
            // Best effort: at least pull the client's process forward.
            app.activate()
            throw ActivationError.windowNotFound
        }

        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        let result = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        app.activate()

        guard result == .success else { throw ActivationError.raiseFailed(result) }
    }

    // MARK: - Accessibility lookup

    /// `CGWindowID` has no public Accessibility counterpart, so match on title first and
    /// fall back to geometry.
    static func accessibilityWindow(matching window: EVEWindow) -> AXUIElement? {
        let application = AXUIElementCreateApplication(window.processIdentifier)

        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
                == .success,
            let windows = value as? [AXUIElement], !windows.isEmpty
        else { return nil }

        if windows.count == 1 { return windows[0] }

        if !window.title.isEmpty,
            let match = windows.first(where: { string(of: $0, kAXTitleAttribute) == window.title })
        {
            return match
        }

        return windows.first { element in
            guard let frame = frame(of: element) else { return false }
            return abs(frame.origin.x - window.frame.origin.x) < 2
                && abs(frame.origin.y - window.frame.origin.y) < 2
                && abs(frame.width - window.frame.width) < 2
                && abs(frame.height - window.frame.height) < 2
        }
    }

    private static func string(of element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = axValue(of: element, kAXPositionAttribute),
            let sizeValue = axValue(of: element, kAXSizeAttribute)
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
            AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }

        return CGRect(origin: position, size: size)
    }

    private static func axValue(of element: AXUIElement, _ attribute: String) -> AXValue? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
            let raw, CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        return (raw as! AXValue)
    }
}
