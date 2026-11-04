//
//  WindowDiscovery.swift
//  eve-operator
//
//  Finds the on-screen windows that belong to `EVEApplication`.
//

import AppKit
import CoreGraphics
import ScreenCaptureKit

enum WindowDiscovery {

    /// EVE also owns menu-bar-sized helper windows and small HUD overlays; anything below
    /// this is not a client window.
    private static let minimumWindowSize = CGSize(width: 200, height: 150)

    /// All shareable windows owned by a running EVE client, in a stable order.
    ///
    /// Uses `onScreenWindowsOnly: false` on purpose: EVE clients are routinely full-screen on
    /// their own Space, and the WindowServer then reports them as off-screen even though they
    /// are perfectly capturable.
    static func shareableWindows() async throws -> [SCWindow] {
        let pids = EVEApplication.processIdentifiers()
        guard !pids.isEmpty else { return [] }

        let content = try await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: false)

        return content.windows
            .filter { window in
                guard let owner = window.owningApplication,
                    pids.contains(owner.processID)
                else { return false }
                guard window.windowLayer == 0 else { return false }
                return window.frame.width >= minimumWindowSize.width
                    && window.frame.height >= minimumWindowSize.height
            }
            .sorted { lhs, rhs in
                let left = lhs.title ?? ""
                let right = rhs.title ?? ""
                return left == right ? lhs.windowID < rhs.windowID : left < right
            }
    }

    /// UI-facing snapshot of the current EVE windows.
    static func currentWindows() async throws -> [EVEWindow] {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return try await shareableWindows().map { window in
            let pid = window.owningApplication?.processID ?? -1
            return EVEWindow(
                id: window.windowID,
                title: window.title ?? "",
                processIdentifier: pid,
                frame: window.frame,
                isActive: pid == frontmost)
        }
    }

    /// Re-resolves a window id to a live `SCWindow`, which is what a capture filter needs.
    static func shareableWindow(id: CGWindowID) async throws -> SCWindow? {
        try await shareableWindows().first { $0.windowID == id }
    }
}
