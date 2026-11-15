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

    var body: some View {

        TabView {
            Tab("Previews", systemImage: "rectangle.grid.3x1") {
                StripSettings()
            }
            Tab("Labels", systemImage: "textformat") {
                LabelSettings()
            }
            Tab("Hot Keys", systemImage: "keyboard") {
                HotKeySettings()
            }
            Tab("Characters", systemImage: "person.2.badge.gearshape") {
                CharacterSettings()
            }
            Tab("Permissions", systemImage: "lock.shield") {
                PermissionSettings()
            }
            Tab("Other", systemImage: "info.circle") {
                OtherView()
            }
        }
        .scenePadding()
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background { WindowConfigurator { SettingsWindow.adopt($0) } }

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
struct BoldLabelStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        LabeledContent {
            configuration.content
        } label: {
            configuration.label.bold()
        }
    }
}


// MARK: - Rows

/// A `Form` in the `.columns` style lays each row out as `label | content`, and a bare
/// `Divider()` — having no label — lands wholly in the content column, so the line starts
/// halfway across. Nothing in the grid vocabulary (`gridCellColumns`, `Section` headers,
/// `frame(maxWidth:)`) reaches back over the label column, so the rule is simply drawn wider
/// than the row and the enclosing `Form` is asked to `.clipped()` the excess.
/// Also used by the Labels tab, which lives in its own file.
struct FullWidthDivider: View {
    var body: some View {
        Divider().padding(.horizontal, -1000).padding(.vertical, 8)
    }
}

/// Also used by the Labels tab, which lives in its own file.
struct SliderRow<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
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
            window.level = .normal
            window.makeKeyAndOrderFront(nil)
            // Survives the app failing to activate, which macOS is free to refuse.
            window.orderFrontRegardless()
        }
    }
}

#Preview("Settings") {
    SettingsView()
}
