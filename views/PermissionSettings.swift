//
//  PermissionSettings.swift
//  eve-operator
//
//  The Permissions tab of the Settings scene: the two TCC permissions the app cannot work
//  without, and read access to EVE's own settings folder, which is not a permission at all
//  but fails in ways that look like one.
//

import AppKit
import SwiftUI

struct PermissionSettings: View {

    private var settings = OverlaySettings.shared
    private var themes = EVEThemeStore.shared

    @State private var hasScreenRecordingPermission = ScreenRecordingPermission.isGranted
    @State private var hasAccessibilityPermission = AccessibilityPermission.isGranted
    @State private var settingsFolderAccess = EVESettingsLocation.Access.notConfigured
    /// Why the last Autodetect from this row came to nothing, if it did.
    @State private var detectionNote: String?

    var body: some View {
        Form {
            Section {

                PermissionRow(
                    title: "Screen Recording",
                    explanation: "Must be granted in order to record windows",
                    isGranted: hasScreenRecordingPermission,
                    action: .init(title: "Open Screen Recording Settings") {
                        grant(
                            ScreenRecordingPermission.request, ScreenRecordingPermission.settingsURL
                        )
                    })
                FullWidthDivider()
                PermissionRow(
                    title: "Accessibility",
                    explanation: "Must be granted in order to activate EVE Online windows",
                    isGranted: hasAccessibilityPermission,
                    action: .init(title: "Open Accessibility Settings") {
                        grant(AccessibilityPermission.request, AccessibilityPermission.settingsURL)
                    })
                FullWidthDivider()
                settingsFolderRow

            }

        }
        .clipped()
        .onAppear(perform: refresh)
        // macOS posts nothing when a TCC decision changes, and polling for one is not worth it:
        // granting happens over in System Settings, so coming back is the only moment the answer
        // can have changed.
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            refresh()
        }
        .onChange(of: themes.status) { refreshFolderAccess() }
    }

    /// Not a TCC permission. The app is not sandboxed and another application's folder under
    /// `~/Library/Application Support` is not protected, so there is nothing to request —
    /// this row reports whether the folder can actually be read, and says what to do about
    /// it when it cannot. The one case where a real macOS permission is involved is an
    /// outright `denied`, which is why that is the only case offering System Settings.
    private var settingsFolderRow: some View {
        PermissionRow(
            title: "EVE Settings Folder",
            explanation:
                "Read so preview labels can match each character's in-game UI color theme",
            isGranted: settingsFolderAccess == .ok,
            detail: folderDetail,
            action: folderAction)
    }

    private var folderDetail: String? {
        if let detectionNote { return detectionNote }
        switch settingsFolderAccess {
        case .ok: return nil
        case .notConfigured: return "Not configured"
        case .notASettingsFolder: return "No settings_Default in this folder"
        case .empty: return "No settings files in this profile yet"
        case .denied(let reason): return "Read denied — \(reason)"
        }
    }

    private var folderAction: PermissionRow.Action? {
        switch settingsFolderAccess {
        case .ok:
            return nil
        case .notConfigured, .notASettingsFolder, .empty:
            // Autodetect is the one-click fix for all three, and the Other tab is where a
            // folder gets chosen by hand if it is not.
            return .init(title: "Autodetect") {
                if case .failure(let failure) = themes.autodetect() {
                    detectionNote = "\(failure.description). Choose it by hand in Other."
                } else {
                    detectionNote = nil
                    // Nothing watches the folder, so a newly detected one is only read
                    // because this says so.
                    themes.reload()
                }
                refreshFolderAccess()
            }
        case .denied:
            return .init(title: "Open Full Disk Access Settings") {
                NSWorkspace.shared.open(FullDiskAccess.settingsURL)
            }
        }
    }

    /// The prompt only ever appears once per install, so the pane is where the switch actually
    /// is — but asking first also registers eve-operator in that pane's list, which is the
    /// difference between flicking a switch and having to add the app by hand.
    private func grant(_ request: @MainActor () -> Bool, _ settingsURL: URL) {
        _ = request()
        NSWorkspace.shared.open(settingsURL)
    }

    private func refresh() {
        hasScreenRecordingPermission = ScreenRecordingPermission.isGranted
        hasAccessibilityPermission = AccessibilityPermission.isGranted
        refreshFolderAccess()
    }

    private func refreshFolderAccess() {
        if settingsFolderAccess == .ok { detectionNote = nil }
        let access = EVESettingsLocation.checkAccess(
            path: settings.eveSettingsFolderPath, profile: settings.eveSettingsProfile)
        if access != settingsFolderAccess { settingsFolderAccess = access }
    }
}

/// Where one thing the app needs stands, and a way to go and fix it. Most of these are TCC
/// permissions; the settings folder is not, which is why the action is a closure rather than
/// a System Settings URL.
private struct PermissionRow: View {

    struct Action {
        let title: String
        let run: @MainActor () -> Void
    }

    let title: String
    let explanation: String
    let isGranted: Bool
    /// Shown instead of the bare "Not granted" when there is something more specific to say.
    var detail: String? = nil
    let action: Action?

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .leading) {
                Label(
                    isGranted ? "Granted" : (detail ?? "Not granted"),
                    systemImage: isGranted
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(isGranted ? Color.green : Color.orange)

                if let action {
                    Button(action.title) { action.run() }
                }
                Text(explanation).font(.caption)

            }
        }

    }
}

#Preview("Permissions") {
    Form {
        PermissionSettings()
    }
    .labeledContentStyle(.boldLabel)
    .scenePadding()
    .frame(width: 460)
}
