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
                // Deliberately not filtered on `windowLayer`. A client usually sits at layer
                // 0, but EVE's fixed-full-screen mode raises the window to the status-bar
                // level (25) while its own client is frontmost, so that it covers the menu
                // bar, and drops it back as soon as it is not — which made the window vanish
                // from the strip for exactly as long as it was in front. Pinning the window
                // to a range of layers instead is no good either: ScreenCaptureKit's idea of
                // the layer visibly lags CoreGraphics', so the value here is whatever it
                // happened to be at the last refresh. Size and title do all the work below,
                // and they already reject everything else EVE publishes: the zero-size
                // placeholders it parks at layer 1000, its menu-bar-sized helpers, and the
                // untitled 500×500 surface at the left edge.
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
