//
//  ContentView.swift
//  eve-operator
//
//  Created by lesha on 4. 11. 2026..
//

import SwiftUI

struct ContentView: View {
    @State private var model = OperatorModel()

    var body: some View {
        NavigationSplitView {
            WindowListSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            WindowDetailView(model: model)
        }
        .task {
            await model.monitor()
        }
        .task(id: model.selectedWindowID) {
            await model.syncCapture()
        }
    }
}

// MARK: - Sidebar

private struct WindowListSidebar: View {
    @Bindable var model: OperatorModel

    var body: some View {
        List(selection: $model.selectedWindowID) {
            Section("Windows") {
                ForEach(model.windows) { window in
                    WindowRow(window: window).tag(window.id)
                }
            }
        }
        .overlay {
            if model.windows.isEmpty {
                EmptySidebarState(model: model)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Re-scan for EVE windows")
            }
        }
        .navigationTitle(EVEApplication.displayName)
    }
}

private struct WindowRow: View {
    let window: EVEWindow

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: window.isActive ? "macwindow.on.rectangle" : "macwindow")
                .foregroundStyle(window.isActive ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(window.characterName ?? window.displayName)
                    .lineLimit(1)
                Text(window.sizeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct EmptySidebarState: View {
    let model: OperatorModel

    var body: some View {
        if !model.isEVEInstalled {
            ContentUnavailableView(
                "EVE not found",
                systemImage: "questionmark.folder",
                description: Text(EVEApplication.bundlePath))
        } else if !model.hasScreenRecordingPermission {
            ContentUnavailableView(
                "Permission needed",
                systemImage: "lock",
                description: Text("Grant Screen Recording to list windows."))
        } else if model.runningClientCount == 0 {
            ContentUnavailableView {
                Label("No EVE clients", systemImage: "moon.zzz")
            } description: {
                Text("Launch EVE Online to see its windows here.")
            } actions: {
                Button("Launch EVE", action: model.launchEVE)
            }
        } else {
            ContentUnavailableView(
                "No windows",
                systemImage: "macwindow",
                description: Text(
                    "\(model.runningClientCount) client(s) running, none showing a window."))
        }
    }
}

// MARK: - Detail

private struct WindowDetailView: View {
    @Bindable var model: OperatorModel

    var body: some View {
        VStack(spacing: 0) {
            PermissionBanners(model: model)

            if let window = model.selectedWindow {
                CapturePane(session: model.capture)
                Divider()
                ControlBar(model: model, window: window)
            } else {
                ContentUnavailableView(
                    "No window selected",
                    systemImage: "rectangle.dashed",
                    description: Text("Pick an EVE window from the sidebar.")
                )
                .frame(maxHeight: .infinity)
            }
        }
        .navigationTitle(model.selectedWindow?.displayName ?? EVEApplication.displayName)
    }
}

private struct CapturePane: View {
    let session: WindowCaptureSession

    var body: some View {
        ZStack {
            CaptureLayerView(contentLayer: session.layer)

            switch session.state {
            case .idle, .starting:
                ProgressView("Starting capture…")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            case .failed(let message):
                ContentUnavailableView(
                    "Capture stopped", systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .background(.ultraThinMaterial)
            case .streaming:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ControlBar: View {
    @Bindable var model: OperatorModel
    let window: EVEWindow

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(window.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(model.activationError == nil ? .secondary : Color.red)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button {
                model.bringSelectedWindowToFront()
            } label: {
                Label("Bring to Front", systemImage: "arrow.up.left.square")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(!model.hasAccessibilityPermission)
            .help(
                model.hasAccessibilityPermission
                    ? "Raise this window and activate its client (⌘↩)"
                    : "Accessibility permission required")
        }
        .padding(12)
    }

    private var status: String {
        if let error = model.activationError { return error }
        let pid = "pid \(window.processIdentifier)"
        switch model.capture.state {
        case .streaming:
            let size = model.capture.frameSize
            return size == .zero
                ? "Streaming · \(pid)"
                : "Streaming \(Int(size.width))×\(Int(size.height)) · \(pid)"
        case .starting: return "Connecting… · \(pid)"
        case .idle: return pid
        case .failed: return "Capture failed · \(pid)"
        }
    }
}

// MARK: - Permissions

private struct PermissionBanners: View {
    let model: OperatorModel

    var body: some View {
        VStack(spacing: 0) {
            if !model.hasScreenRecordingPermission {
                Banner(
                    title:
                        "Screen Recording permission is required to read window titles and stream windows.",
                    actionTitle: "Open Settings",
                    action: model.requestScreenRecordingPermission)
            }
            if !model.hasAccessibilityPermission {
                Banner(
                    title: "Accessibility permission is required to bring a window to the front.",
                    actionTitle: "Grant Access",
                    action: model.requestAccessibilityPermission)
            }
            if let error = model.discoveryError {
                Banner(title: error, actionTitle: "Retry") {
                    Task { await model.refresh() }
                }
            }
        }
    }

    private struct Banner: View {
        let title: String
        let actionTitle: String
        let action: () -> Void

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(title)
                    .font(.callout)
                Spacer(minLength: 8)
                Button(actionTitle, action: action)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.yellow.opacity(0.12))
            Divider()
        }
    }
}

#Preview {
    ContentView()
}
