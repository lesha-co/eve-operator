//
//  OtherView.swift
//  eve-operator
//
//  The Other tab of the Settings scene: the two paths the app needs to be told about — the
//  EVE client itself, and the folder EVE keeps its own settings in — plus the reset.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OtherView: View {

    @Bindable private var settings = OverlaySettings.shared

    private var themes = EVEThemeStore.shared

    @State private var isHoveringTrademark = false

    /// What autodetect last reported, shown in place rather than in an alert.
    @State private var detectionNote: String?

    var body: some View {
        Form {
            LabeledContent("EVE Online") {
                VStack(alignment: .leading, spacing: 6) {
                    // Middle-truncated: the install lives several directories deep and it is
                    // the tail — the shard, `tq` or otherwise — that tells two apart.
                    Text(settings.eveBundlePath)
                        .font(.caption)

                        .lineLimit(2)
                        .truncationMode(.middle)
                        .help(settings.eveBundlePath)

                    if !bundleExists {
                        Label(
                            "No application at this path",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }

                    HStack {
                        Button("Choose\u{2026}", action: choose)
                        Button("Reset to default", action: resetToDefault)
                            .disabled(isDefaultBundlePath)
                    }
                }
            }
            trademarkNotice

            FullWidthDivider()

            settingsFolder

            FullWidthDivider()

            LabeledContent("Defaults") {
                Button("Reset to Defaults") { settings.resetToDefaults() }
                    .disabled(settings.isDefault)
            }

        }
        .clipped()
        // Catches every way the folder can change — Choose, Autodetect, Clear and Reset to
        // Defaults — so none of them has to remember to re-read.
        .onChange(of: settings.eveSettingsFolderPath) { adoptNewFolder() }
    }

    /// Where EVE keeps its own settings: the folder with `settings_Default` inside it. Read
    /// only to find each character's in-game colour theme — nothing here writes to it.
    private var settingsFolder: some View {
        LabeledContent("EVE Settings") {
            VStack(alignment: .leading, spacing: 6) {
                if settings.eveSettingsFolderPath.isEmpty {
                    Text("Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // The directory name is the whole install path with the separators
                    // mangled, so it is long and it is the tail that identifies the shard.
                    Text(settings.eveSettingsFolderPath)
                        .font(.caption)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .help(settings.eveSettingsFolderPath)

                    if !isValidSettingsFolder {
                        Label(
                            "No settings_Default in this folder",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }

                if let detectionNote {
                    Text(detectionNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if profiles.count > 1 {
                    Picker("Profile", selection: $settings.eveSettingsProfile) {
                        ForEach(profiles, id: \.self) { Text($0).tag($0) }
                    }
                    .fixedSize()
                    .onChange(of: settings.eveSettingsProfile) { themes.reload() }
                }

                HStack {
                    Button("Choose\u{2026}", action: chooseSettingsFolder)
                    Button("Autodetect", action: autodetectSettingsFolder)
                    Button("Clear", action: clearSettingsFolder)
                        .disabled(settings.eveSettingsFolderPath.isEmpty)
                        .help("Cleared now, detected again on the next launch")
                }
            }
        }
    }

    private var isValidSettingsFolder: Bool {
        EVESettingsLocation.isValid(settings.eveSettingsFolderPath)
    }

    private var profiles: [String] {
        EVESettingsLocation.profiles(in: settings.eveSettingsFolderPath)
    }

    private func chooseSettingsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the folder containing settings_Default."
        panel.prompt = "Choose"
        // Same reason as the bundle picker above: this lives inside `~/Library`, which the
        // panel hides unless it is already looking at it.
        panel.directoryURL = URL(
            fileURLWithPath: settings.eveSettingsFolderPath.isEmpty
                ? EVESettingsLocation.root : settings.eveSettingsFolderPath)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        detectionNote = nil
        settings.eveSettingsFolderPath = url.standardizedFileURL.path
    }

    private func autodetectSettingsFolder() {
        switch themes.autodetect() {
        case .success(let detection):
            let leaf = (detection.path as NSString).lastPathComponent
            detectionNote =
                detection.wasGuessed
                ? "Several installs found; chose the most recently used (\(leaf))"
                : "Found \(leaf)"
            // `autodetect` has already written the path; if it was unchanged, nothing
            // observes it, so re-read here too.
            adoptNewFolder()
        case .failure(let failure):
            detectionNote = failure.description
        }
    }

    private func clearSettingsFolder() {
        detectionNote = nil
        settings.eveSettingsFolderPath = ""
    }

    /// A different folder can hold entirely different profiles, so the chosen one may no
    /// longer exist.
    private func adoptNewFolder() {
        let available = profiles
        if !available.isEmpty, !available.contains(settings.eveSettingsProfile) {
            settings.eveSettingsProfile = available[0]
        }
        themes.reload()
    }

    /// Spelled out instead of a markdown link in `Text` so the link can pick up the hover
    /// underline and the pointing-hand cursor, neither of which inline markdown gives us.
    private var trademarkNotice: some View {
        HStack(spacing: 0) {
            Text("EVE Online is a trademark of ")
            Link(destination: URL(string: "https://fenris.com")!) {
                Text("Fenris Creations")
                    .foregroundStyle(Color.accentColor)
                    .underline(isHoveringTrademark)
            }
            .pointerStyle(.link)
            .onHover { isHoveringTrademark = $0 }
            Text(".")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Read through the setting rather than `EVEApplication.isInstalled` so the warning is
    /// recomputed when the path changes — a static has nothing for SwiftUI to observe.
    private var bundleExists: Bool {
        FileManager.default.fileExists(atPath: settings.eveBundlePath)
    }

    private var isDefaultBundlePath: Bool {
        settings.eveBundlePath == OverlayMetrics.defaultEVEBundlePath
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the EVE Online client."
        panel.prompt = "Choose"
        // The stock install is inside `~/Library`, which the panel hides unless it is already
        // looking at it, so it opens on the directory holding the current choice.
        panel.directoryURL = URL(fileURLWithPath: settings.eveBundlePath)
            .deletingLastPathComponent()

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.eveBundlePath = url.standardizedFileURL.path
    }

    /// Only the bundle path — the other settings keep whatever the user picked for them.
    private func resetToDefault() {
        settings.eveBundlePath = OverlayMetrics.defaultEVEBundlePath
    }
}

#Preview("Other") {
    Form {
        OtherView()
    }
    .labeledContentStyle(.boldLabel)
    .scenePadding()
    .frame(width: 460)
}
