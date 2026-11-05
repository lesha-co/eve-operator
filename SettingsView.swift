//
//  SettingsView.swift
//  eve-operator
//
//  Contents of the `Settings` scene, reachable from eve-operator → Settings… (⌘,) and from
//  the strip's own context menu.
//

import AppKit
import SwiftUI

struct SettingsView: View {

    @Bindable private var settings = OverlaySettings.shared

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

                LabeledContent("Frames in a row") {
                    Stepper(
                        value: $settings.framesPerRow, in: OverlayMetrics.framesPerRowRange
                    ) {
                        Text("\(settings.framesPerRow)").monospacedDigit()
                    }
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

            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") { settings.resetToDefaults() }
                        .disabled(settings.isDefault)
                }
            }
        }
        .formStyle(.grouped)
        // A grouped Form is a scroll view, and it is a few points taller than the window
        // SwiftUI sizes around it, so it grows a scroller it has no use for.
        .scrollDisabled(true)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background { SettingsWindowConfigurator() }
    }

    private var dragExplanation: String {
        settings.requiresCommandToDrag
            ? "A plain click always raises the client under the pointer. Hold ⌘ and drag to move the strip."
            : "A press that travels more than \(Int(OverlayMetrics.dragThreshold)) pt moves the strip; anything shorter raises the client under the pointer."
    }

    private nonisolated static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

// MARK: - Rows

private struct SliderRow<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    let title: String
    @Binding var value: Value
    let range: ClosedRange<Value>
    let format: (Value) -> String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }
}

// MARK: - Opening the pane

/// Hands the window SwiftUI built for the `Settings` scene over to `SettingsWindow`, and
/// makes it behave like part of an overlay utility rather than a document window.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The view has no window until it is installed in one.
        DispatchQueue.main.async { adopt(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        adopt(nsView.window)
    }

    private func adopt(_ window: NSWindow?) {
        guard let window else { return }
        SettingsWindow.adopt(window)
    }
}

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
