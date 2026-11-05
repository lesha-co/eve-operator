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

struct SettingsView: View {

    @Bindable private var settings = OverlaySettings.shared

    @State private var hasScreenRecordingPermission = ScreenRecordingPermission.isGranted
    @State private var hasAccessibilityPermission = AccessibilityPermission.isGranted

    var body: some View {
        Form {
            Section("Frames") {
                SliderRow(
                    title: "Default opacity",
                    value: $settings.idleOpacity,
                    range: OverlayMetrics.opacityRange,
                    format: Self.percent)

                SliderRow(
                    title: "Focused opacity",
                    value: $settings.hoverOpacity,
                    range: OverlayMetrics.opacityRange,
                    format: Self.percent)

                SliderRow(
                    title: "Frame height",
                    value: $settings.frameHeight,
                    range: OverlayMetrics.frameHeightRange,
                    format: { "\(Int($0.rounded())) pt" })

                IntSliderRow(
                    title: "Frames in a row",
                    value: $settings.framesPerRow,
                    range: OverlayMetrics.framesPerRowRange,
                    format: { "\($0)" })

                Toggle("Previews always on top", isOn: $settings.previewsAlwaysOnTop)
            }

            Section("Character label") {
                ColorPicker(
                    "Color", selection: $settings.labelColor, supportsOpacity: true)

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

            Section("Moving the strip") {
                Picker("Drag", selection: $settings.requiresCommandToDrag) {
                    Text("Drag from anywhere").tag(false)
                    Text("Hold ⌘ to drag").tag(true)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Text(dragExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Screen Recording",
                    explanation: "Reads client window titles and draws the previews.",
                    isGranted: hasScreenRecordingPermission,
                    settingsURL: ScreenRecordingPermission.settingsURL,
                    request: { ScreenRecordingPermission.request() })

                PermissionRow(
                    title: "Accessibility",
                    explanation: "Raises a client when its preview is clicked.",
                    isGranted: hasAccessibilityPermission,
                    settingsURL: AccessibilityPermission.settingsURL,
                    request: { AccessibilityPermission.request() })
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") { settings.resetToDefaults() }
                        .disabled(settings.isDefault)
                }
            }
        }
        .onAppear(perform: refreshPermissions)
        // macOS posts nothing when a TCC decision changes, and polling for one is not worth it:
        // granting happens over in System Settings, so coming back is the only moment the answer
        // can have changed.
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            refreshPermissions()
        }
        .formStyle(.grouped)
        // A grouped Form is a scroll view, and it is a few points taller than the window
        // SwiftUI sizes around it, so it grows a scroller it has no use for.
        .scrollDisabled(true)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background { WindowConfigurator { SettingsWindow.adopt($0) } }
    }

    private var dragExplanation: String {
        settings.requiresCommandToDrag
            ? "A plain click always raises the client under the pointer. Hold ⌘ and drag to move the strip."
            : "A press that travels more than \(Int(OverlayMetrics.dragThreshold)) pt moves the strip; anything shorter raises the client under the pointer."
    }

    private func refreshPermissions() {
        hasScreenRecordingPermission = ScreenRecordingPermission.isGranted
        hasAccessibilityPermission = AccessibilityPermission.isGranted
    }

    private nonisolated static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

// MARK: - Permissions

/// Where one TCC permission stands, and a way to go and fix it.
private struct PermissionRow: View {
    let title: String
    let explanation: String
    let isGranted: Bool
    let settingsURL: URL
    let request: @MainActor () -> Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Label(
                    isGranted ? "Granted" : "Not granted",
                    systemImage: isGranted
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(isGranted ? Color.green : Color.orange)

                if !isGranted {
                    Button("Open System Settings…", action: grant)
                }
            }
        } label: {
            Text(title)
            Text(explanation)
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

// MARK: - Rows

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
