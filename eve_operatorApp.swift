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
        // The app's only surface is the floating overlay panel, which AppKit owns.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let model = OperatorModel()
    private var panel: OverlayPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = OverlayPanel(content: OverlayStripView(model: model))
        panel.show()
        self.panel = panel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        panel?.show()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
