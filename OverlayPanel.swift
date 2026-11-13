//
//  OverlayPanel.swift
//  eve-operator
//
//  A borderless, transparent, always-on-top panel that hosts the strip.
//

import AppKit
import QuartzCore
import SwiftUI

final class OverlayPanel: NSPanel {

    /// `NSWindow`'s own frame autosave is useless here: SwiftUI reports a zero-sized content
    /// view during launch, so AppKit persists an empty frame. Only the anchor is worth saving.
    private static let anchorDefaultsKey = "overlay.anchorTopCentre"
    private static let dockDefaultsKey = "overlay.dock"

    /// What the strip holds on to while its size changes underneath it.
    ///
    /// AppKit re-centres a window whenever its content view controller reports a new preferred
    /// size, which would make the strip crawl across the screen as clients come and go. Both
    /// cases below pin one point of the strip instead, and it grows away from that point.
    private enum Anchor {
        /// Top-centre of the strip in screen coordinates: wherever the user dropped it.
        case free(NSPoint)
        /// A resting place belonging to the screen rather than to the strip, so it also
        /// survives the usable area changing shape.
        case docked(OverlayDock)
    }

    private var anchor: Anchor?
    private var moveObserver: (any NSObjectProtocol)?
    private var screenObserver: (any NSObjectProtocol)?

    private var mouseMonitor: Any?

    private let settings = OverlaySettings.shared

    /// Left-button tracking state; see `handle(_:)`.
    private var pressOrigin: NSPoint?
    private var pressFrameOrigin: NSPoint?
    private weak var pressTarget: MouseTrackingView?
    private var pressCanDrag = true
    private var isDragging = false

    /// Dock easing state; see `ease(to:)`.
    private var easeLink: CADisplayLink?
    private var easeStart = NSPoint.zero
    private var easeTarget = NSPoint.zero
    private var easeStartTime: CFTimeInterval = 0

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
        level = settings.previewsAlwaysOnTop ? OverlayMetrics.overlayWindowLevel : .normal
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

        // A dock is expressed relative to the usable screen, which moves when the Dock is
        // hidden, a display is resized, or the strip's screen goes away altogether.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAnchor() }
        }

        installMouseMonitor()
    }

    deinit {
        easeLink?.invalidate()
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
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
        let desired: NSWindow.Level = alwaysOnTop ? OverlayMetrics.overlayWindowLevel : .normal
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
            // Grabbing the strip mid-flight hands it straight back to the pointer.
            cancelEasing()
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
            if !isDragging {
                isDragging = true
                undock()
            }
            setFrameOrigin(NSPoint(x: origin.x + offset.x, y: origin.y + offset.y))
            return true

        case .leftMouseUp:
            guard pressOrigin != nil else { return false }
            let clicked = isDragging ? nil : pressTarget
            let dragged = isDragging
            pressOrigin = nil
            pressFrameOrigin = nil
            pressTarget = nil
            pressCanDrag = true
            isDragging = false
            if dragged { settle() } else { clicked?.performClick() }
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

        if let anchor, rect.size != frame.size,
            let origin = Self.origin(for: anchor, size: rect.size)
        {
            rect.origin = origin
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

    /// The default is the top-centre dock, so a strip that has never been moved behaves like
    /// one the user put there. Size-independent either way, so it stays correct even while
    /// SwiftUI is still reporting a zero-sized content view.
    func moveToDefaultPosition() {
        anchor = .docked(.topCentre)
        applyAnchor()
        persistAnchor()
    }

    // MARK: - Anchoring

    /// SwiftUI reports a zero-sized content view until its first layout pass; adopting that
    /// as an anchor would pin the strip to the bottom-left corner.
    private var hasUsableSize: Bool { frame.width > 1 && frame.height > 1 }

    private static func origin(for anchor: Anchor, size: NSSize) -> NSPoint? {
        switch anchor {
        case .free(let topCentre):
            return NSPoint(x: topCentre.x - size.width / 2, y: topCentre.y - size.height)
        case .docked(let dock):
            guard let visible = visibleFrame else { return nil }
            return dock.origin(for: size, in: visible)
        }
    }

    private func captureAnchor() {
        guard hasUsableSize else { return }
        // A dock is computed from the screen, never read back off the window: the easing
        // animation moves the window a step at a time and would otherwise undo itself.
        if case .docked = anchor { return }
        anchor = .free(NSPoint(x: frame.midX, y: frame.maxY))
    }

    private func applyAnchor() {
        guard let anchor, let origin = Self.origin(for: anchor, size: frame.size) else { return }
        setFrameOrigin(origin)
    }

    private func persistAnchor() {
        let defaults = UserDefaults.standard
        switch anchor {
        case .free(let point):
            defaults.set(NSStringFromPoint(point), forKey: Self.anchorDefaultsKey)
            defaults.removeObject(forKey: Self.dockDefaultsKey)
        case .docked(let dock):
            defaults.set(dock.rawValue, forKey: Self.dockDefaultsKey)
            defaults.removeObject(forKey: Self.anchorDefaultsKey)
        case nil:
            break
        }
    }

    private static var storedAnchor: Anchor? {
        let defaults = UserDefaults.standard
        // A dock outlives any screen change, so unlike a free anchor it is never discarded.
        if let raw = defaults.string(forKey: dockDefaultsKey),
            let dock = OverlayDock(rawValue: raw)
        {
            return .docked(dock)
        }
        guard let raw = defaults.string(forKey: anchorDefaultsKey) else { return nil }
        let point = NSPointFromString(raw)
        // A screen may have been unplugged since the last run.
        guard let visible = visibleFrame, visible.insetBy(dx: -40, dy: -40).contains(point) else {
            return nil
        }
        return .free(point)
    }

    // MARK: - Docking

    /// Called when a drag ends. A drop near one of the resting places is read as aiming for
    /// it: the strip eases the last few points into position and attaches itself, so from
    /// then on it is re-placed from the dock rather than from wherever it happened to land.
    private func settle() {
        guard let visible = Self.visibleFrame,
            let dock = Self.nearestDock(to: frame, in: visible)
        else { return }

        anchor = .docked(dock)
        persistAnchor()

        ease(
            to: Self.clamped(
                origin: dock.origin(for: frame.size, in: visible), size: frame.size))
    }

    /// Dragging a docked strip detaches it again; where it is dropped decides whether it
    /// re-attaches. Called as the drag starts, while the frame is still the docked one.
    private func undock() {
        guard case .docked = anchor else { return }
        anchor = nil
        captureAnchor()
    }

    /// The dock whose position for this size is within `dockSnapDistance` on both axes, and
    /// the nearest one when a small strip on a small screen is within reach of two.
    private static func nearestDock(to frame: NSRect, in visible: NSRect) -> OverlayDock? {
        let reach = OverlayMetrics.dockSnapDistance
        var nearest: (dock: OverlayDock, distance: CGFloat)?

        for dock in OverlayDock.allCases {
            let origin = dock.origin(for: frame.size, in: visible)
            let dx = origin.x - frame.minX
            let dy = origin.y - frame.minY
            guard abs(dx) <= reach, abs(dy) <= reach else { continue }

            let distance = hypot(dx, dy)
            if nearest == nil || distance < nearest!.distance {
                nearest = (dock, distance)
            }
        }

        return nearest?.dock
    }

    /// Slides the window to `target` over `dockEaseDuration`.
    ///
    /// Driven a frame at a time rather than handed to Core Animation: `NSWindow`'s animator
    /// proxy has no default animation for `frame`, so `animator().setFrame(_:display:)` just
    /// calls the setter and the strip arrives instantly. Moving the window ourselves also
    /// keeps every step going through `setFrameOrigin`, which is where clamping lives.
    private func ease(to target: NSPoint) {
        cancelEasing()
        guard target != frame.origin else { return }

        easeStart = frame.origin
        easeTarget = target
        easeStartTime = CACurrentMediaTime()

        // Display-linked, so the slide is as smooth as the screen allows rather than as
        // smooth as a timer interval guessed in advance.
        let link = displayLink(target: self, selector: #selector(stepEase))
        link.add(to: .main, forMode: .common)
        easeLink = link
    }

    @objc private func stepEase() {
        let elapsed = CACurrentMediaTime() - easeStartTime
        let time = min(elapsed / OverlayMetrics.dockEaseDuration, 1)
        // Ease-out cubic: most of the distance is covered immediately, so the strip reads as
        // being pulled into place rather than flying there.
        let progress = 1 - pow(1 - time, 3)

        setFrameOrigin(
            NSPoint(
                x: easeStart.x + (easeTarget.x - easeStart.x) * progress,
                y: easeStart.y + (easeTarget.y - easeStart.y) * progress))

        if time >= 1 { cancelEasing() }
    }

    /// Ends the slide wherever the window has got to. The display link holds a strong
    /// reference to its target, so this is also what lets the panel be released.
    private func cancelEasing() {
        easeLink?.invalidate()
        easeLink = nil
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

/// A resting place for the strip against the usable area of the screen: either end of the top
/// or bottom edge, or the middle of it.
///
/// The point of docking is what happens afterwards. A docked strip has its origin recomputed
/// from the dock every time it resizes, so it keeps the alignment it was given — flush to the
/// corner, or centred on the edge — instead of drifting by half a frame each time a client
/// comes or goes.
enum OverlayDock: String, CaseIterable {
    case topLeft, topCentre, topRight
    case bottomLeft, bottomCentre, bottomRight

    /// Bottom-left of a strip of `size` docked here, in screen coordinates.
    func origin(for size: NSSize, in visible: NSRect) -> NSPoint {
        let inset = OverlayMetrics.dockInset

        let x: CGFloat =
            switch self {
            case .topLeft, .bottomLeft: visible.minX + inset
            case .topCentre, .bottomCentre: visible.midX - size.width / 2
            case .topRight, .bottomRight: visible.maxX - size.width - inset
            }

        let y: CGFloat =
            switch self {
            case .topLeft, .topCentre, .topRight: visible.maxY - size.height - inset
            case .bottomLeft, .bottomCentre, .bottomRight: visible.minY + inset
            }

        return NSPoint(x: x, y: y)
    }
}
