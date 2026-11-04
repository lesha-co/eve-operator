//
//  OverlayPanel.swift
//  eve-operator
//
//  A borderless, transparent, always-on-top panel that hosts the strip.
//

import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {

    /// Distance from the top of the screen when the panel has no remembered position.
    private static let defaultTopInset: CGFloat = 8

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

    init(content: some View) {
        super.init(
            contentRect: NSRect(
                x: 0, y: 0, width: 320,
                height: OverlayMetrics.frameHeight + OverlayMetrics.padding * 2),
            // `.nonactivatingPanel` keeps focus in EVE when the strip is clicked.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        isFloatingPanel = true
        level = .floating
        // EVE clients are usually full-screen on their own Spaces; the strip has to follow.
        collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
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
    }

    deinit {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
    }

    /// Borderless panels must never steal key/main status, or clicking a thumbnail would
    /// pull focus away from the client we are about to raise.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        if anchor == nil { moveToDefaultPosition() }
        applyAnchor()
        orderFrontRegardless()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect

        if let anchor, rect.size != frame.size {
            rect.origin = NSPoint(x: anchor.x - rect.width / 2, y: anchor.y - rect.height)
        }
        rect.origin = Self.clamped(origin: rect.origin, size: rect.size)

        super.setFrame(rect, display: flag)

        // Re-read the applied frame so clamping is folded back into the anchor.
        captureAnchor()
    }

    func moveToDefaultPosition() {
        guard let visible = Self.visibleFrame else { return }
        // Size-independent, so it stays correct even while SwiftUI is still reporting a
        // zero-sized content view.
        anchor = NSPoint(x: visible.midX, y: visible.maxY - Self.defaultTopInset)
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
        let origin = NSPoint(x: anchor.x - frame.width / 2, y: anchor.y - frame.height)
        setFrameOrigin(Self.clamped(origin: origin, size: frame.size))
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
