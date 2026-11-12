//
//  MenuBarController.swift
//  eve-operator
//
//  The status-item menu: the live clients, then the app-level commands.
//

import AppKit
import Observation

/// Owns the menu-bar item, which exists only while `showsMenuBarIcon` is on.
@MainActor
final class MenuBarController: NSObject {

    private let model: OperatorModel
    private let settings = OverlaySettings.shared

    private var statusItem: NSStatusItem?

    init(model: OperatorModel) {
        self.model = model
        super.init()

        apply()
        observeSetting()
    }

    // MARK: - Visibility

    private func apply() {
        if settings.showsMenuBarIcon {
            guard statusItem == nil else { return }
            statusItem = makeStatusItem()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let image = NSImage(
            systemSymbolName: "record.circle", accessibilityDescription: "EVE Operator")
        image?.isTemplate = true
        item.button?.image = image

        let menu = NSMenu()
        // Items are built in `menuNeedsUpdate(_:)` instead of being kept in step with the
        // 200 ms poll: nothing is on screen until the menu is about to open, so building it
        // then is both cheaper and guaranteed current.
        menu.delegate = self
        item.menu = menu

        return item
    }

    /// There is no view observing this setting — the item is not part of any scene — so the
    /// change is picked up here. `withObservationTracking` is single-shot, hence the re-arm,
    /// and it fires *before* the write lands, hence the hop to the next turn.
    private func observeSetting() {
        withObservationTracking {
            _ = settings.showsMenuBarIcon
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.apply()
                self.observeSetting()
            }
        }
    }

    // MARK: - Actions

    /// Raises the client whose position in the strip is the item's tag. Going through the
    /// slot keeps the out-of-range case — a client that quit while the menu was open — in the
    /// one place that already handles it.
    @objc private func activateSlot(_ sender: NSMenuItem) {
        model.activateSlot(sender.tag)
    }

    @objc private func openSettings() {
        SettingsWindow.open()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Menu contents

extension MenuBarController: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if model.windows.isEmpty {
            // No action, so menu item auto-enabling disables it for us.
            menu.addItem(
                withTitle: model.hasScreenRecordingPermission
                    ? "No clients running" : "Screen Recording not allowed",
                action: nil,
                keyEquivalent: "")
        } else {
            for (slot, window) in model.windows.enumerated() {
                let item = NSMenuItem(
                    title: window.characterName ?? window.displayName,
                    action: #selector(activateSlot(_:)),
                    keyEquivalent: "")
                item.target = self
                item.tag = slot
                // The one the click would be a no-op for, marked rather than disabled.
                item.state = window.isActive ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }
}
