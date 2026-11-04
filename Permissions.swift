//
//  Permissions.swift
//  eve-operator
//
//  TCC permissions required to read window titles, capture windows and raise them.
//

import ApplicationServices
import CoreGraphics

enum ScreenRecordingPermission {
    /// Required to enumerate window titles and to run a capture stream.
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Prompts once per app install; afterwards macOS only shows the Settings pane.
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
}

enum AccessibilityPermission {
    /// Required to raise an individual window of another application.
    static var isGranted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func request() -> Bool {
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
}
