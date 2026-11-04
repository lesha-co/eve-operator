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

    /// Raises `window` and activates its client.
    ///
    /// - Parameter exactWindowRequired: when the client owns a single window, activating the
    ///   process already puts the right window in front, so a failed Accessibility lookup is
    ///   not worth surfacing. Pass `true` only when the distinction matters.
    static func bringToFront(_ window: EVEWindow, exactWindowRequired: Bool = false) throws {
        guard let app = NSRunningApplication(processIdentifier: window.processIdentifier) else {
            throw ActivationError.processGone
        }
        guard AccessibilityPermission.isGranted else {
            throw ActivationError.accessibilityDenied
        }

        guard let element = accessibilityWindow(matching: window) else {
            // Best effort: pulling the client's process forward raises its windows anyway.
            app.activate()
            if exactWindowRequired { throw ActivationError.windowNotFound }
            return
        }

        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        let result = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        app.activate()

        guard result == .success else { throw ActivationError.raiseFailed(result) }
    }

    // MARK: - Accessibility lookup

    /// Resolves the `AXUIElement` for a `CGWindowID`, trying the exact id bridge first and
    /// falling back to title, then geometry.
    static func accessibilityWindow(matching window: EVEWindow) -> AXUIElement? {
        let application = AXUIElementCreateApplication(window.processIdentifier)
        let candidates = windowElements(of: application)
        guard !candidates.isEmpty else { return nil }

        if let match = candidates.first(where: { windowID(of: $0) == window.id }) {
            return match
        }
        if candidates.count == 1 {
            return candidates[0]
        }
        if !window.title.isEmpty,
            let match = candidates.first(where: {
                string(of: $0, kAXTitleAttribute) == window.title
            })
        {
            return match
        }

        return candidates.first { element in
            guard let frame = frame(of: element) else { return false }
            return abs(frame.origin.x - window.frame.origin.x) < 2
                && abs(frame.origin.y - window.frame.origin.y) < 2
                && abs(frame.width - window.frame.width) < 2
                && abs(frame.height - window.frame.height) < 2
        }
    }

    private static func windowElements(of application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
            == .success,
            let windows = value as? [AXUIElement], !windows.isEmpty
        {
            return windows
        }

        // Not every app publishes kAXWindows; these two are usually still there.
        return [kAXMainWindowAttribute, kAXFocusedWindowAttribute].compactMap { attribute in
            var value: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(application, attribute as CFString, &value)
                    == .success,
                let value, CFGetTypeID(value) == AXUIElementGetTypeID()
            else { return nil }
            return (value as! AXUIElement)
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

    // MARK: - CGWindowID bridge

    private typealias GetWindowFunction =
        @convention(c) (
            AXUIElement, UnsafeMutablePointer<CGWindowID>
        ) -> AXError

    /// `_AXUIElementGetWindow` is the only way to map an `AXUIElement` onto a `CGWindowID`.
    /// It is private SPI, so it is resolved at runtime and simply skipped when absent.
    private static let getWindowID: GetWindowFunction? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(rtldDefault, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: GetWindowFunction.self)
    }()

    private static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let getWindowID else { return nil }
        var identifier: CGWindowID = 0
        guard getWindowID(element, &identifier) == .success, identifier != 0 else { return nil }
        return identifier
    }
}
