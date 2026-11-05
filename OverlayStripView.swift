//
//  OverlayStripView.swift
//  eve-operator
//
//  The entire UI: a row of live, mostly-transparent client thumbnails.
//

import SwiftUI

struct OverlayStripView: View {
    @Bindable var model: OperatorModel
    @State private var hoveredID: CGWindowID?

    var body: some View {
        HStack(spacing: OverlayMetrics.spacing) {
            if model.windows.isEmpty {
                StatusPill(
                    text: statusText,
                    systemImage: statusIcon,
                    menuItems: menuItems,
                    action: statusAction)
            } else {
                ForEach(model.windows) { window in
                    if let session = model.sessions[window.id] {
                        ClientFrameView(
                            window: window,
                            session: session,
                            isHovered: hoveredID == window.id,
                            menuItems: menuItems,
                            onHover: { setHover($0, for: window.id) },
                            onClick: { model.activate(window) })
                    }
                }

                if !model.hasAccessibilityPermission {
                    StatusPill(
                        text: "Allow Accessibility\nto raise clients",
                        systemImage: "lock",
                        menuItems: menuItems,
                        action: model.requestAccessibilityPermission)
                }

                if let error = model.activationError {
                    StatusPill(
                        text: error,
                        systemImage: "exclamationmark.triangle",
                        menuItems: menuItems,
                        action: { model.activationError = nil })
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

    private func setHover(_ hovering: Bool, for id: CGWindowID) {
        if hovering {
            hoveredID = id
        } else if hoveredID == id {
            hoveredID = nil
        }
    }

    // MARK: - Empty state

    private var statusText: String {
        if !model.isEVEInstalled {
            return "EVE not found"
        }
        if !model.hasScreenRecordingPermission {
            return "Allow Screen Recording"
        }
        if let error = model.discoveryError {
            return error
        }
        if model.runningClientCount == 0 {
            return "Launch EVE"
        }
        return "\(model.runningClientCount) client(s), no windows yet"
    }

    private var statusIcon: String {
        if !model.isEVEInstalled { return "questionmark.folder" }
        if !model.hasScreenRecordingPermission { return "lock" }
        if model.discoveryError != nil { return "exclamationmark.triangle" }
        if model.runningClientCount == 0 { return "play.circle" }
        return "moon.zzz"
    }

    private var statusAction: () -> Void {
        if !model.isEVEInstalled { return {} }
        if !model.hasScreenRecordingPermission { return model.requestScreenRecordingPermission }
        if model.discoveryError != nil { return { Task { await model.refresh() } } }
        if model.runningClientCount == 0 { return model.launchEVE }
        return { Task { await model.refresh() } }
    }

    /// "Rescan" is the 2-second poll run on demand: it re-enumerates EVE's windows, then starts
    /// a capture stream for any that appeared and tears down the streams of any that vanished.
    /// Useful when a thumbnail has gone stale, redundant otherwise.
    private var menuItems: [MouseTracker.MenuEntry] {
        var items: [MouseTracker.MenuEntry] = [
            .init(title: "Rescan EVE Windows", action: { Task { await model.refresh() } })
        ]
        if model.isEVEInstalled {
            items.append(.init(title: "Launch Another Client", action: model.launchEVE))
        }
        items.append(.separator)
        items.append(.init(title: "Quit eve-operator", action: { NSApp.terminate(nil) }))
        return items
    }
}

// MARK: - Client frame

private struct ClientFrameView: View {
    let window: EVEWindow
    let session: WindowCaptureSession
    let isHovered: Bool
    let menuItems: [MouseTracker.MenuEntry]
    let onHover: (Bool) -> Void
    let onClick: () -> Void

    private var opacity: Double {
        isHovered ? OverlayMetrics.hoverOpacity : OverlayMetrics.idleOpacity
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
            width: OverlayMetrics.frameWidth(forAspectRatio: window.aspectRatio),
            height: OverlayMetrics.frameHeight
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
    let text: String
    let systemImage: String
    let menuItems: [MouseTracker.MenuEntry]
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text(text)
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
        .opacity(isHovered ? OverlayMetrics.statusHoverOpacity : OverlayMetrics.statusIdleOpacity)
        .overlay {
            MouseTracker(onHover: { isHovered = $0 }, onClick: action, menuItems: menuItems)
        }
        .animation(.easeOut(duration: OverlayMetrics.hoverAnimationDuration), value: isHovered)
    }
}
