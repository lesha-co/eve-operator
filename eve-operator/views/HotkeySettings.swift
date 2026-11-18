//
//  HotkeySettings.swift
//  eve-operator
//
//  Created by lesha on 13. 11. 2026..
//

import SwiftUI

enum HotKeyWarning: Hashable {
    case fnKeyMode
    case justCtrl
    case unavailableHotkey(hotkeys: String)

    var description: String {
        switch self {
            case .fnKeyMode:
                "This keyboard sends F1…F12 as media keys. Turn on Keyboard → “Use F1, F2, etc. keys as standard function keys”, or hold fn."
            case .justCtrl:
                "macOS reserves ⌃F1…⌃F8 for keyboard navigation and will keep them. Add another modifier."
            case .unavailableHotkey(let keys):
                "Another application already owns \(keys)."
        }

    }

}

struct HotKeySettings: View {

    @State private var rowWidth: CGFloat = 0

    @Bindable private var settings = OverlaySettings.shared

    /// The live window list, so the list below can say which of the keys reach a client that
    /// is actually running.
    private var model = OperatorModel.shared

    /// Keys are handed out by position in here, so this is the list to print.
    private var roster = CharacterRoster.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Enable hotkeys") {
                    Toggle("Raise previews with function keys", isOn: $settings.hotKeysEnabled)
                }

                Toggle(
                    "Only while an EVE client is frontmost",
                    isOn: $settings.hotKeysOnlyWhileClientActive)

                LabeledContent("Modifiers") {
                    HStack(spacing: 6) {
                        ForEach(HotKeyModifiers.all, id: \.rawValue, content: modifierButton)

                        Text("+ F1—F12")
                    }

                }
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    rowWidth = $0
                }

            }
            if !warnings.isEmpty {
                Section {
                    ForEach(warnings, id: \.self) { warning in
                        LabeledContent {
                            Text(warning.description)
                                .fixedSize(horizontal: false, vertical: true)
                        } label: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(.orange)
                        .frame(width: rowWidth > 0 ? rowWidth : nil, alignment: .leading)

                    }
                }
            }

            Section {

                LabeledContent("Previews") {
                    Toggle("Show hotkey in label", isOn: $settings.showsHotKeyInLabel)
                }
            }
        }

        .formStyle(.columns)
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

    /// Everything that can leave a key registered but silent. Each is a condition this app
    /// cannot fix on the user's behalf, so saying so is all that is left.
    private var warnings: [HotKeyWarning] {
        guard settings.hotKeysEnabled else { return [] }
        var warnings: [HotKeyWarning] = []

        // A bare function key never reaches an application unless the keyboard is in "standard
        // function keys" mode — otherwise F1 is brightness-down and the press is consumed long
        // before any hot key is consulted. Read from the global domain, where the Keyboard
        // pane writes it; absent means off, which is the factory setting.
        if settings.hotKeyModifiers.isEmpty,
            !UserDefaults.standard.bool(forKey: "com.apple.keyboard.fnState")
        {
            warnings.append(.fnKeyMode)
        }

        // macOS keeps ⌃F1…⌃F8 for keyboard navigation and wins the dispatch, so control on its
        // own is the one combination that registers and then never fires.
        if settings.hotKeyModifiers == .control {
            warnings.append(.justCtrl)
        }

        if !model.unavailableHotKeySlots.isEmpty {
            let keys = model.unavailableHotKeySlots.map {
                HotKeyMonitor.label(forSlot: $0, modifiers: settings.hotKeyModifiers)
            }

            warnings.append(.unavailableHotkey(hotkeys: keys.joined(separator: ", ")))
        }

        return warnings
    }
}

#Preview {
    Form {
        HotKeySettings()
    }
    .scenePadding()
    .frame(width: 460)

}
