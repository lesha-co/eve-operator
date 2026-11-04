//
//  OperatorModel.swift
//  eve-operator
//
//  App state: discovered windows, selection, permissions and the capture session.
//

import AppKit
import Observation

@MainActor
@Observable
final class OperatorModel {

    private(set) var windows: [EVEWindow] = []
    private(set) var discoveryError: String?
    private(set) var hasScreenRecordingPermission = ScreenRecordingPermission.isGranted
    private(set) var hasAccessibilityPermission = AccessibilityPermission.isGranted
    private(set) var isEVEInstalled = EVEApplication.isInstalled
    private(set) var runningClientCount = 0

    var selectedWindowID: CGWindowID?
    var activationError: String?

    @ObservationIgnored let capture = WindowCaptureSession()

    private static let refreshInterval = Duration.seconds(2)

    var selectedWindow: EVEWindow? {
        windows.first { $0.id == selectedWindowID }
    }

    // MARK: - Discovery

    /// Polls for window changes until the enclosing `task` is cancelled.
    func monitor() async {
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
        isEVEInstalled = EVEApplication.isInstalled
        runningClientCount = EVEApplication.runningInstances().count

        guard hasScreenRecordingPermission else {
            windows = []
            discoveryError = nil
            return
        }

        do {
            windows = try await WindowDiscovery.currentWindows()
            discoveryError = nil
        } catch {
            windows = []
            discoveryError = error.localizedDescription
        }

        reconcileSelection()
        if let selectedWindow {
            await capture.adapt(to: selectedWindow)
        }
    }

    private func reconcileSelection() {
        if let id = selectedWindowID, windows.contains(where: { $0.id == id }) { return }
        selectedWindowID = windows.first?.id
    }

    // MARK: - Capture

    /// Drives the capture session from the current selection.
    func syncCapture() async {
        guard let id = selectedWindowID else {
            await capture.stop()
            return
        }
        await capture.start(windowID: id)
    }

    // MARK: - Actions

    func bringSelectedWindowToFront() {
        guard let window = selectedWindow else { return }
        do {
            try WindowActivator.bringToFront(window)
            activationError = nil
        } catch {
            activationError = error.localizedDescription
        }
    }

    func requestScreenRecordingPermission() {
        ScreenRecordingPermission.request()
        NSWorkspace.shared.open(ScreenRecordingPermission.settingsURL)
    }

    func requestAccessibilityPermission() {
        AccessibilityPermission.request()
    }

    func launchEVE() {
        guard isEVEInstalled else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: EVEApplication.bundleURL, configuration: configuration)
    }
}
