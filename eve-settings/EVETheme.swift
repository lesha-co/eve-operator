//
//  EVETheme.swift
//  eve-operator
//
//  One custom EVE UI colour theme, as defined in an account's
//  `core_user_<id>.dat` → `ui / custom_color_themes`. See `docs/eve-settings-files.md` §6.
//

import Foundation
import SwiftUI

nonisolated struct EVETheme: Sendable, Equatable, Identifiable {

    /// The GUID a character's `windows / wndColorThemeID` points at.
    let id: String
    let name: String

    /// The theme's focus colour, raw `#AARRGGBB` as EVE wrote it. A theme defines four
    /// colours but only this one is read — see `OverlayMetrics.defaultMirroredThemeChannel`.
    /// Kept as text rather than as a `Color` so a theme can be carried off the main actor
    /// and shown verbatim in the UI.
    let focus: String

    init(id: String, name: String, focus: String) {
        self.id = id
        self.name = name
        self.focus = focus
    }

    /// Reads one entry of the `themes` array. A theme with no focus colour is no use to us
    /// and is dropped rather than carried around half-empty.
    init?(_ value: MarshalValue) {
        guard let id = value["id"]?.textValue, !id.isEmpty,
            let focus = value[OverlayMetrics.defaultMirroredThemeChannel]?.textValue,
            Self.normalized(focus) != nil
        else { return nil }
        self.init(id: id, name: value["name"]?.textValue ?? id, focus: focus)
    }

    var color: Color? {
        Self.color(fromARGB: focus)
    }

    /// The colour in the form EVE's own share string uses: six digits, alpha dropped.
    var shareHex: String? {
        guard let raw = Self.normalized(focus) else { return nil }
        return "#" + raw.suffix(6).uppercased()
    }

    /// EVE writes `#AARRGGBB` — alpha first, the opposite of this app's own `#RRGGBBAA`.
    static func color(fromARGB hex: String) -> Color? {
        guard let raw = normalized(hex), let packed = UInt32(raw, radix: 16) else { return nil }
        return Color(
            .sRGB,
            red: Double((packed >> 16) & 0xFF) / 255,
            green: Double((packed >> 8) & 0xFF) / 255,
            blue: Double(packed & 0xFF) / 255,
            opacity: Double((packed >> 24) & 0xFF) / 255)
    }

    /// Accepts `#AARRGGBB` and `#RRGGBB`, with or without the `#`, and returns eight digits.
    private static func normalized(_ hex: String) -> String? {
        var raw = hex.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.allSatisfy(\.isHexDigit) else { return nil }
        switch raw.count {
        case 8: return raw
        case 6: return "ff" + raw
        default: return nil
        }
    }
}
