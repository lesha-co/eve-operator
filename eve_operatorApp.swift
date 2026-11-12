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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = OverlayPanel(content: OverlayStripView(model: model))
        panel.show()
        self.panel = panel

        // Touched here rather than lazily from a view so that the one-off autodetect happens
        // on a first launch even if the settings pane is never opened. The read itself runs
        // off the main actor and never again touches disk from the polling path.
        _ = EVEThemeStore.shared
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        panel?.show()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
