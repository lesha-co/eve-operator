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
                    ForEach(row) { window in
                        if let session = model.sessions[window.id] {
                            ClientFrameView(
                                window: window,
                                session: session,
                                settings: settings,
                                isHovered: hoveredID == window.id,
                                menuItems: menuItems,
                                onHover: { setHover($0, for: window.id) },
                                onClick: { model.activate(window) })
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
        .background { MouseTracker(menuItems: menuItems) }
        .task { await model.monitor() }
    }

    /// Frames wrap once a row is full, so a fleet of clients stays on screen.
    private var rows: [[EVEWindow]] {
        let perRow = max(1, settings.framesPerRow)
        return stride(from: 0, to: model.windows.count, by: perRow).map { start in
            Array(model.windows[start..<min(start + perRow, model.windows.count)])
        }
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

    /// "Rescan" is the 2-second poll run on demand: it re-enumerates EVE's windows, then starts
    /// a capture stream for any that appeared and tears down the streams of any that vanished.
    /// Useful when a thumbnail has gone stale, redundant otherwise.
    private var menuItems: [MouseTracker.MenuEntry] {
        [
            .init(title: "Rescan EVE Windows", action: { Task { await model.refresh() } }),
            .init(title: "Settings…", action: { SettingsWindow.open() }),
            .separator,
            .init(title: "Quit eve-operator", action: { NSApp.terminate(nil) }),
        ]
    }
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
    let isHovered: Bool
    let menuItems: [MouseTracker.MenuEntry]
    let onHover: (Bool) -> Void
    let onClick: () -> Void

    private var opacity: Double {
        isHovered ? settings.hoverOpacity : settings.idleOpacity
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CaptureLayerView(
                contentLayer: session.layer,
                opacity: opacity,
                cornerRadius: OverlayMetrics.cornerRadius)

            RoundedRectangle(cornerRadius: OverlayMetrics.cornerRadius)
                .strokeBorder(
                    window.isActive ? Color.accentColor : Color.white.opacity(0.3),
                    lineWidth: window.isActive ? 1.5 : 1
                )
                .opacity(opacity)

            Text(window.characterName ?? window.displayName)
                .font(.system(size: OverlayMetrics.labelFontSize, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(4)
                .opacity(opacity)
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
                .font(.system(size: OverlayMetrics.labelFontSize + 1, weight: .medium))
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
