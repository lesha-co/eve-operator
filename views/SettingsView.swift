//
//  SettingsView.swift
//  eve-operator
//
//  Contents of the `Settings` scene, reachable from eve-operator → Settings… (⌘,) and from
//  the strip's own context menu.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {

    var body: some View {

        TabView {
            Tab("Previews", systemImage: "rectangle.on.rectangle") {
                StripSettings()
            }
            Tab("Labels", systemImage: "textformat") {
                LabelSettings()
            }
            Tab("Hot Keys", systemImage: "keyboard") {
                HotKeySettings()
            }
            Tab("Permissions", systemImage: "lock.shield") {
                PermissionSettings()
            }
            Tab("Other", systemImage: "info.circle") {
                OtherView()
            }
        }
        .labeledContentStyle(.boldLabel)
        .scenePadding()
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background { WindowConfigurator { SettingsWindow.adopt($0) } }

    }
}

private struct OtherView: View {

    @Bindable private var settings = OverlaySettings.shared

    @State private var isHoveringTrademark = false

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

            LabeledContent("Defaults") {
                Button("Reset to Defaults") { settings.resetToDefaults() }
                    .disabled(settings.isDefault)
            }

        }
        .clipped()
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

// MARK: - Tabs

private struct StripSettings: View {

    @Bindable private var settings = OverlaySettings.shared

    var body: some View {

        Form {

            SliderRow(
                title: "Default opacity",
                value: $settings.idleOpacity,
                range: OverlayMetrics.opacityRange,
                format: percent)

            SliderRow(
                title: "Focused opacity",
                value: $settings.hoverOpacity,
                range: OverlayMetrics.opacityRange,
                format: percent)

            SliderRow(
                title: "Frame height",
                value: $settings.frameHeight,
                range: OverlayMetrics.frameHeightRange,
                step: 10.0,
                format: { "\(Int($0.rounded())) pt" })

            Picker("Frames in a row", selection: $settings.framesPerRow) {
                ForEach(OverlayMetrics.framesPerRowRange, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)

            Toggle("Previews always on top", isOn: $settings.previewsAlwaysOnTop)

            FullWidthDivider()

            LabeledContent("Dragging") {
                Picker("Drag", selection: $settings.requiresCommandToDrag) {
                    VStack(alignment: .leading) {
                        Text("Drag from anywhere")
                        Text(
                            "A press that travels more than \(Int(OverlayMetrics.dragThreshold)) pt moves the strip; anything shorter raises the client under the pointer."
                        ).font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(false)
                    VStack(alignment: .leading) {
                        Text("Hold ⌘ to drag")
                        Text(
                            "A plain click always raises the client under the pointer. Hold ⌘ and drag to move the strip."
                        ).font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(true)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            FullWidthDivider()

            PortraitView()
        }
        .clipped()
    }

    private nonisolated func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct LabelSettings: View {

    @Bindable private var settings = OverlaySettings.shared

    var body: some View {
        Form {
            Section {
                ColorPicker("Color", selection: $settings.labelColor, supportsOpacity: true)

                SliderRow(
                    title: "Font size",
                    value: $settings.labelFontSize,
                    range: OverlayMetrics.labelFontSizeRange,
                    step: 1.0,
                    format: { "\(Int($0.rounded())) pt" })

                LabeledContent("Position") {
                    VStack(spacing: 6) {
                        Picker("Edge", selection: $settings.labelEdge) {
                            ForEach(LabelEdge.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Alignment", selection: $settings.labelAlignment) {
                            ForEach(LabelAlignment.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
        }
    }
}

private struct HotKeySettings: View {

    @Bindable private var settings = OverlaySettings.shared

    /// The live window list, so the table below says which character each key raises rather
    /// than merely that it raises "the third one".
    private var model = OperatorModel.shared

    var body: some View {
        Form {

            Toggle("Raise previews with function keys", isOn: $settings.hotKeysEnabled)
                .bold()

            Group {
                LabeledContent("Modifiers") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            ForEach(HotKeyModifiers.all, id: \.rawValue, content: modifierButton)
                        }
                        Text(modifierExplanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Toggle(
                    "Only while an EVE client is frontmost",
                    isOn: $settings.hotKeysOnlyWhileClientActive)

                Toggle("Show the key in each label", isOn: $settings.showsHotKeyInLabel)

                FullWidthDivider()

                LabeledContent("Keys") { assignments }
            }
            // Everything below the first toggle is moot while the keys are off — but the
            // toggle itself has to stay live, so the group is disabled rather than the form.
            .disabled(!settings.hotKeysEnabled)

            ForEach(warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .clipped()
    }

    // MARK: - Pieces

    private func modifierButton(_ modifier: HotKeyModifiers) -> some View {
        Toggle(
            modifier.symbols,
            isOn: Binding(
                get: { settings.hotKeyModifiers.contains(modifier) },
                set: { isOn in
                    if isOn {
                        settings.hotKeyModifiers.insert(modifier)
                    } else {
                        settings.hotKeyModifiers.remove(modifier)
                    }
                })
        )
        .toggleStyle(.button)
    }

    private var modifierExplanation: String {
        settings.hotKeyModifiers.isEmpty
            ? "No modifier: the bare function key, which EVE no longer sees while the key is taken."
            : "EVE keeps the bare function keys; only the combination above is taken."
    }

    /// What each key raises at this moment. Positions are the strip's own order, so this is
    /// also the answer to "which frame is third".
    @ViewBuilder private var assignments: some View {
        if model.windows.isEmpty {
            Text("No clients are running.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(model.windows.enumerated()), id: \.element.id) { slot, window in
                    HStack(spacing: 6) {
                        Text(
                            HotKeyMonitor.label(
                                forSlot: slot, modifiers: settings.hotKeyModifiers) ?? "—"
                        )
                        .monospaced()
                        .foregroundStyle(
                            HotKeyMonitor.label(forSlot: slot, modifiers: settings.hotKeyModifiers)
                                == nil ? .secondary : .primary)
                        Text("→")
                            .foregroundStyle(.secondary)
                        Text(window.characterName ?? window.displayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption)
                }
            }
        }
    }

    /// Everything that can leave a key registered but silent. Each is a condition this app
    /// cannot fix on the user's behalf, so saying so is all that is left.
    private var warnings: [String] {
        guard settings.hotKeysEnabled else { return [] }
        var warnings: [String] = []

        // A bare function key never reaches an application unless the keyboard is in "standard
        // function keys" mode — otherwise F1 is brightness-down and the press is consumed long
        // before any hot key is consulted. Read from the global domain, where the Keyboard
        // pane writes it; absent means off, which is the factory setting.
        if settings.hotKeyModifiers.isEmpty,
            !UserDefaults.standard.bool(forKey: "com.apple.keyboard.fnState")
        {
            warnings.append(
                "This keyboard sends F1…F12 as media keys. Turn on Keyboard → “Use F1, F2, etc. keys as standard function keys”, or hold fn."
            )
        }

        // macOS keeps ⌃F1…⌃F8 for keyboard navigation and wins the dispatch, so control on its
        // own is the one combination that registers and then never fires.
        if settings.hotKeyModifiers == .control {
            warnings.append(
                "macOS reserves ⌃F1…⌃F8 for keyboard navigation and will keep them. Add another modifier."
            )
        }

        if !model.unavailableHotKeySlots.isEmpty {
            let keys = model.unavailableHotKeySlots.compactMap {
                HotKeyMonitor.label(forSlot: $0, modifiers: settings.hotKeyModifiers)
            }
            warnings.append(
                "Another application already owns \(keys.joined(separator: ", ")).")
        }

        return warnings
    }
}

private struct PermissionSettings: View {

    @State private var hasScreenRecordingPermission = ScreenRecordingPermission.isGranted
    @State private var hasAccessibilityPermission = AccessibilityPermission.isGranted

    var body: some View {
        Form {
            Section {

                PermissionRow(
                    title: "Screen Recording",
                    explanation: "Must be granted in order to record windows",
                    isGranted: hasScreenRecordingPermission,
                    settingsURL: ScreenRecordingPermission.settingsURL,
                    buttonText: "Open Screen Recording Settings",
                    request: { ScreenRecordingPermission.request() })
                FullWidthDivider()
                PermissionRow(
                    title: "Accessibility",
                    explanation: "Must be granted in order to activate EVE Online windows",
                    isGranted: hasAccessibilityPermission,
                    settingsURL: AccessibilityPermission.settingsURL,
                    buttonText: "Open Accessibility Settings",
                    request: { AccessibilityPermission.request() })

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
    }

    private func refresh() {
        hasScreenRecordingPermission = ScreenRecordingPermission.isGranted
        hasAccessibilityPermission = AccessibilityPermission.isGranted
    }
}

// MARK: - Permissions

/// Where one TCC permission stands, and a way to go and fix it.
private struct PermissionRow: View {
    let title: String
    let explanation: String
    let isGranted: Bool
    let settingsURL: URL
    let buttonText: String
    let request: @MainActor () -> Bool

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .leading) {
                Label(
                    isGranted ? "Granted" : "Not granted",
                    systemImage: isGranted
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(isGranted ? Color.green : Color.orange)

                Button(buttonText, action: grant)
                Text(explanation).font(.caption)

            }
        }

    }

    /// The prompt only ever appears once per install, so the pane is where the switch actually
    /// is — but asking first also registers eve-operator in that pane's list, which is the
    /// difference between flicking a switch and having to add the app by hand.
    private func grant() {
        _ = request()
        NSWorkspace.shared.open(settingsURL)
    }
}

// MARK: - Styling

/// Bolds every `LabeledContent` label in the pane, so the label column reads as the heading it
/// is. Rebuilding the row as a plain `LabeledContent` rather than, say, an `HStack` is what keeps
/// the `Form`'s label/content columns: a style that lays the two slots out itself arrives at the
/// form as one opaque view and lands wholly in the content column. SwiftUI resolves the nested
/// row against the *next* style along, so this neither recurses nor loses the columns.
///
/// Controls that render their own label — `ColorPicker`, `Toggle` — are not `LabeledContent` and
/// are not reached by this; they bold their label at the call site.
private struct BoldLabelStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        LabeledContent {
            configuration.content
        } label: {
            configuration.label.bold()
        }
    }
}

extension LabeledContentStyle where Self == BoldLabelStyle {
    fileprivate static var boldLabel: Self { Self() }
}

// MARK: - Rows

/// A `Form` in the `.columns` style lays each row out as `label | content`, and a bare
/// `Divider()` — having no label — lands wholly in the content column, so the line starts
/// halfway across. Nothing in the grid vocabulary (`gridCellColumns`, `Section` headers,
/// `frame(maxWidth:)`) reaches back over the label column, so the rule is simply drawn wider
/// than the row and the enclosing `Form` is asked to `.clipped()` the excess.
private struct FullWidthDivider: View {
    var body: some View {
        Divider().padding(.horizontal, -1000).padding(.vertical, 8)
    }
}

private struct SliderRow<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    let title: String
    @Binding var value: Value
    let range: ClosedRange<Value>
    var step: Value.Stride?
    let format: (Value) -> String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                // `Slider` has no "unstepped" value for `step`, so the two inits are distinct.
                if let step {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }
}

/// `Slider` is floating-point only, so a whole-number setting travels as a `Double` and is
/// rounded back on the way in.
private struct IntSliderRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let format: (Int) -> String

    var body: some View {
        SliderRow(
            title: title,
            value: Binding(
                get: { Double(value) },
                set: { value = Int($0.rounded()) }),
            range: Double(range.lowerBound)...Double(range.upperBound),
            step: 1,
            format: { format(Int($0.rounded())) })
    }
}

// MARK: - Opening the pane

/// Shows the `Settings` scene from outside SwiftUI.
enum SettingsWindow {

    /// SwiftUI owns the window's lifetime; this is only a handle for raising it again.
    private static weak var window: NSWindow?

    static func adopt(_ window: NSWindow) {
        guard Self.window !== window else { return }
        Self.window = window

        // EVE clients are usually full-screen on their own Space, so a stock settings window
        // opens on whichever Space it was first built on rather than the one the user is
        // looking at.
        window.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])
        window.hidesOnDeactivate = false

        // It only floats for as long as it is being used: see `open()`.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { Self.window?.level = .normal }
        }
    }

    private static var resignObserver: (any NSObjectProtocol)?

    /// `NSApp.sendAction(Selector(("showSettingsWindow:")))` is the usual recipe and is
    /// useless here: it reports success and no window appears. SwiftUI does not implement
    /// that action — it installs a private callback object as the target of the menu item it
    /// adds — so driving that menu item is the only thing that actually works. The item is
    /// found by its ⌘, key equivalent rather than its title, which is localised.
    static func open() {
        // The strip is a non-activating panel, so the app is almost never frontmost here.
        NSApp.activate()

        if let menu = NSApp.mainMenu?.items.first?.submenu,
            let index = menu.items.firstIndex(where: {
                $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command
            })
        {
            menu.performActionForItem(at: index)
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }

        // SwiftUI creates the window on the next turn of the run loop, and an already-open
        // one is left wherever it was, so raising it is a separate step either way.
        DispatchQueue.main.async {
            NSApp.activate()
            guard let window else { return }
            // Floating *only* until the user switches away, which drops it back to .normal.
            // A full-screen client sits at the status-bar level while it is frontmost and
            // would otherwise swallow this window the instant it appeared, but a settings
            // pane permanently pinned over everything is its own kind of annoying.
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            // Survives the app failing to activate, which macOS is free to refuse.
            window.orderFrontRegardless()
        }
    }
}

#Preview("Settings") {
    SettingsView()
}

#Preview("Labels") {
    Form {
        LabelSettings()
    }
    .labeledContentStyle(.boldLabel)
    .scenePadding()
    .frame(width: 460)
}

#Preview("Permissions") {
    Form {
        PermissionSettings()
    }
    .labeledContentStyle(.boldLabel)
    .scenePadding()
    .frame(width: 460)
}

#Preview("Other") {
    Form {
        OtherView()
    }
    .labeledContentStyle(.boldLabel)
    .scenePadding()
    .frame(width: 460)
}
