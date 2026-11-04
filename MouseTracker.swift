//
//  MouseTracker.swift
//  eve-operator
//
//  Hover and click handling for a window that never becomes key.
//
//  SwiftUI's `onHover`/`onTapGesture` only fire dependably in the active app, and the overlay
//  is a non-activating panel by design. An AppKit tracking area with `.activeAlways` plus
//  `acceptsFirstMouse` keeps the strip responsive while EVE stays focused.
//

import AppKit
import SwiftUI

struct MouseTracker: NSViewRepresentable {
    var onHover: (Bool) -> Void = { _ in }
    var onClick: () -> Void = {}
    /// Items for the right-click menu; an empty title inserts a separator.
    var menuItems: [MenuEntry] = []

    struct MenuEntry {
        let title: String
        let action: () -> Void

        static let separator = MenuEntry(title: "", action: {})
    }

    func makeNSView(context: Context) -> MouseTrackingView {
        let view = MouseTrackingView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: MouseTrackingView, context: Context) {
        update(nsView)
    }

    private func update(_ view: MouseTrackingView) {
        view.onHover = onHover
        view.onClick = onClick
        view.menu = menuItems.isEmpty ? nil : Self.makeMenu(menuItems)
    }

    private static func makeMenu(_ entries: [MenuEntry]) -> NSMenu {
        let menu = NSMenu()
        for entry in entries {
            menu.addItem(entry.title.isEmpty ? .separator() : ClosureMenuItem(entry))
        }
        return menu
    }
}

final class MouseTrackingView: NSView {

    var onHover: (Bool) -> Void = { _ in }
    var onClick: () -> Void = {}

    private var trackingArea: NSTrackingArea?
    private var isInside = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isInside else { return }
        isInside = true
        onHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard isInside else { return }
        isInside = false
        onHover(false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil, isInside {
            isInside = false
            onHover(false)
        }
    }

    /// The overlay is never the active app, so the first click has to count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // ⌘-drag anywhere on the strip repositions it; a plain click activates the client.
        if event.modifierFlags.contains(.command) {
            window?.performDrag(with: event)
        } else {
            onClick()
        }
    }
}

/// `NSMenuItem` that calls a closure, so menus can be declared inline.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ entry: MouseTracker.MenuEntry) {
        handler = entry.action
        super.init(title: entry.title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func fire() { handler() }
}
