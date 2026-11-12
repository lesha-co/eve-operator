//
//  OverlayStripView.swift
//  eve-operator
//
//  The entire UI: rows of live, mostly-transparent client thumbnails.
//

import SwiftUI

struct OverlayStripView: View {
    @Bindable var model: OperatorModel
    @Bindable private var settings = OverlaySettings.shared

    @State private var hoveredID: CGWindowID?

    var body: some View {
        VStack(spacing: OverlayMetrics.spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: OverlayMetrics.spacing) {
                    ForEach(row) { slot in
                        if let session = model.sessions[slot.window.id] {
                            ClientFrameView(
                                window: slot.window,
                                session: session,
                                settings: settings,
                                labelColor: LabelColors.color(for: slot.window),
                                hotKeyLabel: hotKeyLabel(for: slot),
                                isHovered: hoveredID == slot.window.id,
                                menuItems: menuItems,
                                onHover: { setHover($0, for: slot.window.id) },
                                onClick: { model.activate(slot.window) })
                        }
                    }
                }
            }

            if !notices.isEmpty {
                HStack(spacing: OverlayMetrics.spacing) {
                    ForEach(notices) { notice in
                        StatusPill(notice: notice, settings: settings, menuItems: menuItems)
                    }
                }
            }
        }
        .padding(OverlayMetrics.padding)
        .fixedSize()
        // Keeps a real AppKit view under every pixel of the panel, including the padding.
        // Bare SwiftUI hosting view counts as window background, which AppKit handles itself
        // instead of delivering the event. It also puts the context menu on the whole strip.
        .background {
            MouseTracker(menuItems: menuItems)
            WindowConfigurator { window in
                (window as? OverlayPanel)?.setAlwaysOnTop(settings.previewsAlwaysOnTop)
            }
        }
        .task { await model.monitor() }
    }

    /// Frames wrap once a row is full, so a fleet of clients stays on screen. Slot numbers
    /// run across the whole strip, not across a row: they are positions in `model.windows`,
    /// which is what a hot key resolves against.
    private var rows: [[Slot]] {
        let perRow = max(1, settings.framesPerRow)
        let slots = model.windows.enumerated().map { Slot(number: $0.offset, window: $0.element) }
        return stride(from: 0, to: slots.count, by: perRow).map { start in
            Array(slots[start..<min(start + perRow, slots.count)])
        }
    }

    /// The key that raises this frame, when there is one and it is wanted in the label.
    private func hotKeyLabel(for slot: Slot) -> String? {
        guard settings.hotKeysEnabled, settings.showsHotKeyInLabel else { return nil }
        return HotKeyMonitor.label(forSlot: slot.number, modifiers: settings.hotKeyModifiers)
    }

    private func setHover(_ hovering: Bool, for id: CGWindowID) {
        if hovering {
            hoveredID = id
        } else if hoveredID == id {
            hoveredID = nil
        }
    }

    // MARK: - Notices

    /// With no clients there is nothing to say either: the strip draws nothing at all rather
    /// than explaining itself, and `OverlayPanel` stops reacting to the mouse while it is
    /// empty. Notices only ever accompany frames that are already on screen.
    private var notices: [Notice] {
        guard !model.windows.isEmpty else { return [] }

        var notices: [Notice] = []
        if !model.hasAccessibilityPermission {
            notices.append(
                Notice(
                    id: "accessibility",
                    text: "Allow Accessibility\nto raise clients",
                    systemImage: "lock",
                    action: model.requestAccessibilityPermission))
        }
        if let error = model.activationError {
            notices.append(
                Notice(
                    id: "activation",
                    text: error,
                    systemImage: "exclamationmark.triangle",
                    action: { model.activationError = nil }))
        }
        return notices
    }

    private var menuItems: [MouseTracker.MenuEntry] {
        [
            .init(title: "Settings…", action: { SettingsWindow.open() }),
            .init(title: "Quit", action: { NSApp.terminate(nil) }),
        ]
    }
}

// MARK: - Slot

/// A client together with its position in the strip, which is also the hot key that raises it.
private struct Slot: Identifiable {
    let number: Int
    let window: EVEWindow

    var id: CGWindowID { window.id }
}

// MARK: - Notice

private struct Notice: Identifiable {
    let id: String
    let text: String
    let systemImage: String
    let action: () -> Void
}

// MARK: - Client frame

private struct ClientFrameView: View {
    let window: EVEWindow
    let session: WindowCaptureSession
    let settings: OverlaySettings
    /// Resolved by `OverlayStripView` rather than looked up here: this view is rebuilt for
    /// every capture frame and has no business doing dictionary lookups.
    let labelColor: Color
    let hotKeyLabel: String?
    let isHovered: Bool
    let menuItems: [MouseTracker.MenuEntry]
    let onHover: (Bool) -> Void
    let onClick: () -> Void

    private var opacity: Double {
        isHovered ? settings.hoverOpacity : settings.idleOpacity
    }

    /// The caption is the one part of a frame that has to stay readable, so it only follows
    /// the configured opacity down to a floor.
    private var labelOpacity: Double {
        OverlayMetrics.labelOpacity(opacity)
    }

    /// Only the frontmost client is picked out, and only while the user wants it to be.
    private var isHighlighted: Bool {
        settings.highlightsActiveClient && window.isActive
    }

    private var label: String {
        let name = window.characterName ?? window.displayName
        guard let hotKeyLabel else { return name }
        return "\(hotKeyLabel) · \(name)"
    }

    var body: some View {
        ZStack(alignment: settings.labelPlacement) {
            CaptureLayerView(
                contentLayer: session.layer,
                opacity: opacity,
                cornerRadius: OverlayMetrics.cornerRadius)

            RoundedRectangle(cornerRadius: OverlayMetrics.cornerRadius)
                .strokeBorder(
                    labelColor,
                    lineWidth: isHighlighted
                        ? OverlayMetrics.activeBorderWidth : 0
                ).opacity(labelOpacity)

            Text(label)
                .font(.system(size: settings.labelFontSize, weight: .medium))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(4)
                .opacity(labelOpacity)
        }
        .frame(
            width: OverlayMetrics.frameWidth(
                forAspectRatio: window.aspectRatio, height: settings.frameHeight),
            height: settings.frameHeight
        )
        .overlay {
            MouseTracker(onHover: onHover, onClick: onClick, menuItems: menuItems)
        }
        .animation(.easeOut(duration: OverlayMetrics.hoverAnimationDuration), value: isHovered)
        .help("Click to bring \(window.displayName) to the front · drag to move the strip")
    }
}

// MARK: - Status pill

private struct StatusPill: View {
    let notice: Notice
    let settings: OverlaySettings
    let menuItems: [MouseTracker.MenuEntry]

    @State private var isHovered = false

    private var opacity: Double {
        OverlayMetrics.statusOpacity(isHovered ? settings.hoverOpacity : settings.idleOpacity)
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: notice.systemImage)
            Text(notice.text)
                .font(.system(size: settings.labelFontSize, weight: .medium))
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            .black.opacity(0.65), in: RoundedRectangle(cornerRadius: OverlayMetrics.cornerRadius)
        )
        .frame(maxWidth: OverlayMetrics.statusMaxWidth)
        .opacity(opacity)
        .overlay {
            MouseTracker(onHover: { isHovered = $0 }, onClick: notice.action, menuItems: menuItems)
        }
        .animation(.easeOut(duration: OverlayMetrics.hoverAnimationDuration), value: isHovered)
    }
}
