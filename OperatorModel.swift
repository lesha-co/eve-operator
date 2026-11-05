//
//  OperatorModel.swift
//  eve-operator
//
//  App state: discovered windows, permissions and one live capture session per window.
//

import AppKit
import Observation
import ScreenCaptureKit

@MainActor
@Observable
final class OperatorModel {

    private(set) var windows: [EVEWindow] = []
    /// One live stream per discovered window, keyed by `CGWindowID`.
    private(set) var sessions: [CGWindowID: WindowCaptureSession] = [:]

    private(set) var hasScreenRecordingPermission = ScreenRecordingPermission.isGranted
    private(set) var hasAccessibilityPermission = AccessibilityPermission.isGranted

    var activationError: String?

    private let settings = OverlaySettings.shared

    private static let refreshInterval = Duration.seconds(2)

    // MARK: - Discovery

    /// Polls for window changes until the enclosing `task` is cancelled.
    func monitor() async {
        // An empty strip draws nothing, so there is no pill left to ask for this. Without
        // the prompt a first run would just sit there blank with no way to find out why.
        if !hasScreenRecordingPermission { ScreenRecordingPermission.request() }

        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    func refresh() async {
        // Permission checks are TCC round-trips, so only re-ask while still missing.
        if !hasScreenRecordingPermission {
            hasScreenRecordingPermission = ScreenRecordingPermission.isGranted
        }
        if !hasAccessibilityPermission {
            hasAccessibilityPermission = AccessibilityPermission.isGranted
        }
        guard hasScreenRecordingPermission else {
            windows = []
            await stopAllSessions()
            return
        }

        do {
            let shareable = try await WindowDiscovery.shareableWindows()
            windows = WindowDiscovery.snapshot(of: shareable)
            await syncSessions(with: shareable)
        } catch {
            windows = []
            await stopAllSessions()
        }
    }

    // MARK: - Capture

    private func syncSessions(with shareable: [SCWindow]) async {
        let live = Set(shareable.map(\.windowID))

        for (id, session) in sessions where !live.contains(id) {
            sessions[id] = nil
            await session.stop()
        }

        for window in shareable {
            if let session = sessions[window.windowID] {
                await session.updatePreferredHeight(settings.frameHeight)
                await session.adapt(to: EVEWindow(window, frontmostProcess: nil))
            } else {
                let session = WindowCaptureSession(preferredHeight: settings.frameHeight)
                sessions[window.windowID] = session
                await session.start(window: window)
            }
        }
    }

    private func stopAllSessions() async {
        let running = sessions.values
        sessions = [:]
        for session in running {
            await session.stop()
        }
    }

    // MARK: - Actions

    func activate(_ window: EVEWindow) {
        // A client with a single window is fully raised by activating its process, so only
        // demand an exact Accessibility match when one process owns several windows.
        let siblings = windows.count { $0.processIdentifier == window.processIdentifier }
        do {
            try WindowActivator.bringToFront(window, exactWindowRequired: siblings > 1)
            activationError = nil
        } catch {
            activationError = error.localizedDescription
        }
    }

    func requestAccessibilityPermission() {
        AccessibilityPermission.request()
    }
}
