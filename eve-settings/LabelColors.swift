//
//  LabelColors.swift
//  eve-operator
//
//  The one place a character's label colour is worked out, so the swatch in the settings
//  pane and the text drawn on the strip cannot disagree.
//

import SwiftUI

@MainActor
enum LabelColors {

    /// Why a label ended up the colour it did — the settings pane shows this, the strip
    /// only uses `color`.
    enum Source: Equatable {
        /// The global `labelColor`, because this character has no entry of its own.
        case global
        case custom
        /// Mirrored from EVE, showing the colour in EVE's own six-digit share form.
        case mirrored(String)
        /// Mirroring was asked for but there is nothing to mirror; falls back to global.
        case unavailable(String)
    }

    struct Resolution {
        let color: Color
        let source: Source
    }

    static func color(for window: EVEWindow) -> Color {
        resolve(window.characterName).color
    }

    static func resolve(_ characterName: String?) -> Resolution {
        let settings = OverlaySettings.shared
        let fallback = Resolution(color: settings.labelColor, source: .global)

        guard let characterName else { return fallback }

        switch settings.labelColorSetting(for: characterName) {
        case .inherited:
            return fallback
        case .fixed(let color):
            return Resolution(color: color, source: .custom)
        case .mirrored:
            return mirror(characterName, fallback: fallback)
        }
    }

    private static func mirror(_ characterName: String, fallback: Resolution) -> Resolution {
        let settings = OverlaySettings.shared

        guard !settings.eveSettingsFolderPath.isEmpty else {
            return Resolution(color: fallback.color, source: .unavailable("folder not set"))
        }
        guard
            let id = CharacterRoster.shared.characters.first(where: { $0.name == characterName })?
                .characterID
        else {
            return Resolution(color: fallback.color, source: .unavailable("ID unknown"))
        }
        guard let theme = EVEThemeStore.shared.theme(forCharacterID: id) else {
            // EVE's built-in palettes are not reproduced here — there is no source for them,
            // and a guessed colour is worse than an honest fallback.
            return Resolution(color: fallback.color, source: .unavailable("stock theme"))
        }
        guard let color = theme.color, let hex = theme.shareHex else {
            return Resolution(color: fallback.color, source: .unavailable("unreadable color"))
        }
        return Resolution(color: color, source: .mirrored(hex))
    }
}
