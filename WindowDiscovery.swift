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

    /// Only the real client window carries a title ("EVE - Character Name"). Every helper
    /// window EVE publishes at layer 0 is untitled, and one of them — a square surface parked
    /// at the left edge — grows to 500×500, which clears `minimumWindowSize` and used to show
    /// up in the strip as "Untitled window". Untitled windows therefore have to be
    /// client-sized before we believe them, which still covers a client that is logging in
    /// and has not set its title yet.
    private static let minimumUntitledWindowSize = CGSize(width: 1000, height: 700)

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
                let required =
                    (window.title ?? "").isEmpty
                    ? minimumUntitledWindowSize : minimumWindowSize
                return window.frame.width >= required.width
                    && window.frame.height >= required.height
            }
            .sorted { lhs, rhs in
                let left = lhs.title ?? ""
                let right = rhs.title ?? ""
                return left == right ? lhs.windowID < rhs.windowID : left < right
            }
    }

    /// UI-facing snapshot of the current EVE windows.
    static func currentWindows() async throws -> [EVEWindow] {
        snapshot(of: try await shareableWindows())
    }

    /// Maps already-fetched `SCWindow`s, so callers that also need the live objects (to open a
    /// capture stream) don't have to pay for a second `SCShareableContent` round-trip.
    static func snapshot(of windows: [SCWindow]) -> [EVEWindow] {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return windows.map { EVEWindow($0, frontmostProcess: frontmost) }
    }

    /// Re-resolves a window id to a live `SCWindow`, which is what a capture filter needs.
    static func shareableWindow(id: CGWindowID) async throws -> SCWindow? {
        try await shareableWindows().first { $0.windowID == id }
    }
}
