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

    // MARK: - Polling

    /// UI-facing snapshot of the current EVE windows, read straight from the WindowServer.
    ///
    /// Deliberately avoids `SCShareableContent`, which the strip used to poll several times a
    /// second. That call allocates an `SCRunningApplication` per running process and an
    /// `SCWindow` per window on the system, and ScreenCaptureKit logs an `os_log` line for
    /// every one of them — on a normal desktop, around 700 lines per call. At the poll rate
    /// below that is thousands of lines a second, which is enough for `libsystem_trace` to
    /// quarantine the process for "high logging volume" and start dropping every log the app
    /// makes, including its crash-relevant ones. `CGWindowListCopyWindowInfo` answers the
    /// same question silently, so ScreenCaptureKit is now only consulted when a capture
    /// stream actually has to be opened.
    static func currentWindows() -> [EVEWindow] {
        let pids = EVEApplication.processIdentifiers()
        guard !pids.isEmpty else { return [] }

        // `.optionAll` rather than `.optionOnScreenOnly` for the same reason the
        // ScreenCaptureKit path passes `onScreenWindowsOnly: false`: EVE clients are routinely
        // full-screen on their own Space, and the WindowServer then reports them as off-screen
        // even though they are perfectly capturable.
        guard
            let entries = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }

        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier

        return
            entries
            .compactMap { entry -> EVEWindow? in
                guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                    pids.contains(pid),
                    let id = entry[kCGWindowNumber as String] as? CGWindowID,
                    let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                    let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
                else { return nil }

                // `kCGWindowName` is only populated with Screen Recording permission, which
                // callers already gate on; without it every window reads as untitled and the
                // size floor below is what keeps helpers out.
                let title = entry[kCGWindowName as String] as? String ?? ""
                guard isClientWindow(title: title, frame: frame) else { return nil }

                return EVEWindow(
                    id: id,
                    title: title,
                    processIdentifier: pid,
                    frame: frame,
                    isActive: pid == frontmost)
            }
            .sorted { lhs, rhs in
                lhs.title == rhs.title ? lhs.id < rhs.id : lhs.title < rhs.title
            }
    }

    // MARK: - Capture

    /// All shareable windows owned by a running EVE client, in a stable order.
    ///
    /// Only needed to build an `SCContentFilter`, so call it when a stream is about to open
    /// and not on the polling path — see `currentWindows()`.
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
                return isClientWindow(title: window.title ?? "", frame: window.frame)
            }
            .sorted { lhs, rhs in
                let left = (lhs.title ?? "", lhs.windowID)
                let right = (rhs.title ?? "", rhs.windowID)
                return left.0 == right.0 ? left.1 < right.1 : left.0 < right.0
            }
    }

    /// Re-resolves a window id to a live `SCWindow`, which is what a capture filter needs.
    static func shareableWindow(id: CGWindowID) async throws -> SCWindow? {
        try await shareableWindows().first { $0.windowID == id }
    }

    // MARK: - Filtering

    /// Shared by both lookups so the strip and the capture path never disagree about what
    /// counts as a client window.
    ///
    /// Deliberately not filtered on window layer. A client usually sits at layer 0, but EVE's
    /// fixed-full-screen mode raises the window to the status-bar level (25) while its own
    /// client is frontmost, so that it covers the menu bar, and drops it back as soon as it is
    /// not — which made the window vanish from the strip for exactly as long as it was in
    /// front. Size and title do all the work instead, and they already reject everything else
    /// EVE publishes: the zero-size placeholders it parks at layer 1000, its menu-bar-sized
    /// helpers, and the untitled 500×500 surface at the left edge.
    private static func isClientWindow(title: String, frame: CGRect) -> Bool {
        let required = title.isEmpty ? minimumUntitledWindowSize : minimumWindowSize
        return frame.width >= required.width && frame.height >= required.height
    }

}
