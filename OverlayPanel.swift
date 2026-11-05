//
//  OverlayPanel.swift
//  eve-operator
//
//  A borderless, transparent, always-on-top panel that hosts the strip.
//

import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {

    /// `NSWindow`'s own frame autosave is useless here: SwiftUI reports a zero-sized content
    /// view during launch, so AppKit persists an empty frame. Only the anchor is worth saving.
    private static let anchorDefaultsKey = "overlay.anchorTopCentre"

    /// Top-centre of the strip in screen coordinates.
    ///
    /// AppKit re-centres a window whenever its content view controller reports a new preferred
    /// size, which would make the strip crawl across the screen as clients come and go. Pinning
    /// the top centre keeps it put while it grows symmetrically.
    private var anchor: NSPoint?
    private var moveObserver: (any NSObjectProtocol)?

    private var mouseMonitor: Any?

    private let settings = OverlaySettings.shared

    /// Left-button tracking state; see `handle(_:)`.
    private var pressOrigin: NSPoint?
    private var pressFrameOrigin: NSPoint?
    private weak var pressTarget: MouseTrackingView?
    private var pressCanDrag = true
    private var isDragging = false

    init(content: some View) {
        super.init(
            contentRect: NSRect(
                x: 0, y: 0, width: 320,
                height: OverlayMetrics.defaultFrameHeight + OverlayMetrics.padding * 2),
            // `.nonactivatingPanel` keeps focus in EVE when the strip is clicked.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        isFloatingPanel = true
        level = settings.previewsAlwaysOnTop ? .floating : .normal
        // EVE clients are usually full-screen on their own Spaces; the strip has to follow.
        collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Dragging is driven by the event monitors instead, so a press that never moves stays
        // a click. AppKit's own background drag consumes mouse-down unconditionally.
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        isReleasedWhenClosed = false

        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        contentViewController = controller

        anchor = Self.storedAnchor

        // Dragging happens window-server side and bypasses `setFrame`.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.captureAnchor()
                self?.persistAnchor()
            }
        }

        installMouseMonitor()
    }

    deinit {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    }

    /// Borderless panels must never steal key/main status, or clicking a thumbnail would
    /// pull focus away from the client we are about to raise.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        if anchor == nil { moveToDefaultPosition() }
        applyAnchor()
        orderFrontRegardless()
        updateInteractivity()
    }

    /// Driven from the strip's `WindowConfigurator`, so flipping the setting takes effect at
    /// once instead of at the next launch.
    func setAlwaysOnTop(_ alwaysOnTop: Bool) {
        let desired: NSWindow.Level = alwaysOnTop ? .floating : .normal
        guard level != desired else { return }
        level = desired
        // Promoting a window does not re-order it; without this it would stay buried until
        // something else happened to raise it.
        if alwaysOnTop, hasContent { orderFrontRegardless() }
    }

    // MARK: - Empty state

    /// True once the strip holds at least one frame. With no clients it shrinks to its own
    /// padding and draws nothing, and an invisible window must not go on swallowing clicks
    /// meant for whatever is behind it.
    private var hasContent: Bool {
        frame.height > OverlayMetrics.emptyStripHeight + 1
    }

    /// The window is left in place rather than ordered out: AppKit stops laying out a window
    /// that is off-screen, so it would never learn that a client had appeared and never come
    /// back. Transparent and inert is the same thing to look at and keeps SwiftUI running.
    private func updateInteractivity() {
        ignoresMouseEvents = !hasContent
    }

    // MARK: - Pointer handling

    private static let watchedEvents: NSEvent.EventTypeMask = [
        .leftMouseDown, .leftMouseDragged, .leftMouseUp,
    ]

    /// Resolves press-versus-drag for the left button.
    ///
    /// Hover and the context menu are fine coming through AppKit, but the mouse-down is not:
    /// between first-mouse handling and `isMovableByWindowBackground` there is more than one
    /// way for it to be spent before a view sees it. A local monitor runs inside
    /// `NSApplication.sendEvent(_:)`, ahead of all of that, and can swallow what it uses.
    private func installMouseMonitor() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: Self.watchedEvents,
            handler: { [weak self] event in
                guard let self else { return event }
                return self.handle(event) ? nil : event
            })
    }

    /// - Returns: `true` when the event belonged to the strip and must not travel further.
    private func handle(_ event: NSEvent) -> Bool {
        // The monitor runs ahead of `ignoresMouseEvents`, so the empty state is checked here
        // too or an invisible strip would still eat the press.
        guard isVisible, hasContent else { return false }
        // `locationInWindow` is relative to the event's own window, which is not necessarily
        // this one. Screen coordinates mean the same thing whoever received the event.
        let point = NSEvent.mouseLocation

        switch event.type {
        case .leftMouseDown:
            guard frame.contains(point) else { return false }
            pressOrigin = point
            pressFrameOrigin = frame.origin
            pressTarget = trackingView(at: point)
            pressCanDrag =
                !settings.requiresCommandToDrag || event.modifierFlags.contains(.command)
            isDragging = false
            return true

        case .leftMouseDragged:
            guard let start = pressOrigin, let origin = pressFrameOrigin else { return false }
            // In ⌘-to-drag mode an unmodified press is swallowed but never moves the strip,
            // so it still resolves to a click on mouse-up.
            guard pressCanDrag else { return true }
            let offset = CGPoint(x: point.x - start.x, y: point.y - start.y)
            guard isDragging || hypot(offset.x, offset.y) >= OverlayMetrics.dragThreshold else {
                return true
            }
            isDragging = true
            setFrameOrigin(NSPoint(x: origin.x + offset.x, y: origin.y + offset.y))
            return true

        case .leftMouseUp:
            guard pressOrigin != nil else { return false }
            let clicked = isDragging ? nil : pressTarget
            pressOrigin = nil
            pressFrameOrigin = nil
            pressTarget = nil
            pressCanDrag = true
            isDragging = false
            clicked?.performClick()
            return true

        default:
            return false
        }
    }

    private func trackingView(at screenPoint: NSPoint) -> MouseTrackingView? {
        guard frame.contains(screenPoint), let contentView else { return nil }
        return contentView.hitTest(convertPoint(fromScreen: screenPoint)) as? MouseTrackingView
    }

    // MARK: - Placement

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect

        if let anchor, rect.size != frame.size {
            rect.origin = NSPoint(x: anchor.x - rect.width / 2, y: anchor.y - rect.height)
        }
        rect.origin = Self.clamped(origin: rect.origin, size: rect.size)

        super.setFrame(rect, display: flag)

        // Re-read the applied frame so clamping is folded back into the anchor.
        captureAnchor()
        updateInteractivity()
    }

    /// `setFrameOrigin` does not route through `setFrame(_:display:)`, so dragging would
    /// otherwise be able to push the strip off-screen.
    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(Self.clamped(origin: point, size: frame.size))
    }

    func moveToDefaultPosition() {
        guard let visible = Self.visibleFrame else { return }
        // Size-independent, so it stays correct even while SwiftUI is still reporting a
        // zero-sized content view.
        anchor = NSPoint(x: visible.midX, y: visible.maxY - OverlayMetrics.defaultTopInset)
        applyAnchor()
        persistAnchor()
    }

    // MARK: - Anchoring

    /// SwiftUI reports a zero-sized content view until its first layout pass; adopting that
    /// as an anchor would pin the strip to the bottom-left corner.
    private var hasUsableSize: Bool { frame.width > 1 && frame.height > 1 }

    private func captureAnchor() {
        guard hasUsableSize else { return }
        anchor = NSPoint(x: frame.midX, y: frame.maxY)
    }

    private func applyAnchor() {
        guard let anchor else { return }
        setFrameOrigin(NSPoint(x: anchor.x - frame.width / 2, y: anchor.y - frame.height))
    }

    private func persistAnchor() {
        guard let anchor else { return }
        UserDefaults.standard.set(NSStringFromPoint(anchor), forKey: Self.anchorDefaultsKey)
    }

    private static var storedAnchor: NSPoint? {
        guard let raw = UserDefaults.standard.string(forKey: anchorDefaultsKey) else { return nil }
        let point = NSPointFromString(raw)
        // A screen may have been unplugged since the last run.
        guard let visible = visibleFrame, visible.insetBy(dx: -40, dy: -40).contains(point) else {
            return nil
        }
        return point
    }

    // MARK: - Geometry helpers

    private static var visibleFrame: NSRect? {
        (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
    }

    private static func clamped(origin: NSPoint, size: NSSize) -> NSPoint {
        guard let visible = visibleFrame else { return origin }
        return NSPoint(
            x: min(max(origin.x, visible.minX), max(visible.maxX - size.width, visible.minX)),
            y: min(max(origin.y, visible.minY), max(visible.maxY - size.height, visible.minY)))
    }
}
