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

    /// The strip and the settings pane read the same instance: the hot-key tab lists what each
    /// key currently raises, which is a question only the live window list can answer.
    static let shared = OperatorModel()

    private(set) var windows: [EVEWindow] = []
    /// One live stream per discovered window, keyed by `CGWindowID`.
    private(set) var sessions: [CGWindowID: WindowCaptureSession] = [:]

    private(set) var hasScreenRecordingPermission = ScreenRecordingPermission.isGranted
    private(set) var hasAccessibilityPermission = AccessibilityPermission.isGranted

    var activationError: String?

    /// Positions whose hot key another application had already claimed.
    private(set) var unavailableHotKeySlots: [Int] = []

    private let settings = OverlaySettings.shared

    @ObservationIgnored private lazy var hotKeys = HotKeyMonitor { [weak self] slot in
        self?.activateSlot(slot)
    }

    private static let refreshInterval = Duration.milliseconds(200)

    /// Floor on how often a window the WindowServer lists but ScreenCaptureKit does not may be
    /// chased, so an unresolvable window cannot reintroduce per-poll `SCShareableContent`
    /// calls — see `WindowDiscovery.currentWindows()`.
    private static let resolveRetryInterval = Duration.seconds(2)

    @ObservationIgnored private var lastResolveAttempt: ContinuousClock.Instant?

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
            syncHotKeys()
            await stopAllSessions()
            return
        }

        // Assigned only on a real change: `@Observable` tracks the write, not the value, so
        // assigning an identical list five times a second would redraw everything observing it
        // five times a second.
        let found = WindowDiscovery.currentWindows()
        if found != windows { windows = found }

        syncHotKeys()
        await syncSessions(with: windows)
    }

    // MARK: - Capture

    private func syncSessions(with windows: [EVEWindow]) async {
        let live = Set(windows.map(\.id))

        for (id, session) in sessions where !live.contains(id) {
            sessions[id] = nil
            await session.stop()
        }

        for window in windows {
            guard let session = sessions[window.id] else { continue }
            await session.updatePreferredHeight(settings.frameHeight)
            await session.adapt(to: window)
        }

        let unstarted = windows.filter { sessions[$0.id] == nil }
        if !unstarted.isEmpty { await startSessions(for: unstarted) }
    }

    /// Opening a stream is the one thing that needs a live `SCWindow`, and resolving one costs
    /// a full `SCShareableContent` round-trip, so this runs only when a window has actually
    /// appeared — never on every poll.
    private func startSessions(for windows: [EVEWindow]) async {
        if let last = lastResolveAttempt, last.duration(to: .now) < Self.resolveRetryInterval {
            return
        }

        let wanted = Set(windows.map(\.id))
        let shareable = (try? await WindowDiscovery.shareableWindows()) ?? []

        for window in shareable
        where wanted.contains(window.windowID) && sessions[window.windowID] == nil {
            let session = WindowCaptureSession(preferredHeight: settings.frameHeight)
            sessions[window.windowID] = session
            await session.start(window: window)
        }

        // A window ScreenCaptureKit has not offered up yet is usually a client still coming
        // up, which resolves on a later pass — but it can also never resolve, so back off
        // instead of asking again at the polling rate.
        lastResolveAttempt = wanted.allSatisfy { sessions[$0] != nil } ? nil : .now
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

    /// Raises the client in position `slot` of the strip, counting from zero. Out-of-range
    /// slots are ignored: a key can outlive the client it was registered for by one poll.
    func activateSlot(_ slot: Int) {
        guard windows.indices.contains(slot) else { return }
        activate(windows[slot])
    }

    func requestAccessibilityPermission() {
        AccessibilityPermission.request()
    }

    // MARK: - Hot keys

    /// Keeps the registered keys in step with what is on screen. Driven from the poll rather
    /// than from observation so that the window list, the frontmost application and the
    /// settings are all read at one consistent moment; `HotKeyMonitor.sync` returns
    /// immediately when nothing has changed, which is every pass but a handful.
    private func syncHotKeys() {
        // Holding the keys only while a client is in front is what makes an unmodified
        // function key tolerable: F1 goes on belonging to every other application, and is
        // only taken for as long as the press could have been meant for a client.
        let withheld =
            settings.hotKeysOnlyWhileClientActive && !windows.contains(where: \.isActive)
        let slots = settings.hotKeysEnabled && !withheld ? windows.count : 0

        hotKeys.sync(slotCount: slots, modifiers: settings.hotKeyModifiers)

        if hotKeys.unavailableSlots != unavailableHotKeySlots {
            unavailableHotKeySlots = hotKeys.unavailableSlots
        }
    }
}
