//
//  eve_operatorApp.swift
//  eve-operator
//
//  Created by lesha on 4. 11. 2026..
//

import SwiftUI

@main
struct eve_operatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The strip itself is an AppKit panel the delegate owns; this scene exists so the
        // settings pane gets its standard eve-operator → Settings… (⌘,) menu item.
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let model = OperatorModel.shared
    private var panel: OverlayPanel?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = OverlayPanel(content: OverlayStripView(model: model))
        panel.show()
        self.panel = panel

        menuBar = MenuBarController(model: model)

        // Touched here rather than lazily from a view so that the one-off autodetect happens
        // on a first launch even if the settings pane is never opened. The read itself runs
        // off the main actor and never again touches disk from the polling path.
        _ = EVEThemeStore.shared

        // Not now: SwiftUI installs the Settings… menu item that `SettingsWindow.open()`
        // drives while it builds the scene, so the next turn of the run loop is the earliest
        // this can work.
        Task { openSettingsIfNoClients() }
    }

    /// With no clients the strip draws nothing at all — no frames, not even a pill to click —
    /// so a launch that finds none has nothing to show for itself beyond the menu-bar item,
    /// which is optional. The settings pane is also where the reason usually is: a missing
    /// Screen Recording permission reads as no clients here, and counts as none on purpose.
    private func openSettingsIfNoClients() {
        // Asked directly rather than read off `model.windows`, which the strip's poll has not
        // necessarily filled in yet, and cheap enough to ask twice: one WindowServer query.
        let hasClients =
            ScreenRecordingPermission.isGranted && !WindowDiscovery.currentWindows().isEmpty
        guard !hasClients else { return }

        SettingsWindow.open()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        panel?.show()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
