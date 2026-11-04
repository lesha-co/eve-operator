//
//  EVEWindow.swift
//  eve-operator
//
//  A value-type snapshot of one on-screen EVE client window.
//

import CoreGraphics
import Foundation

struct EVEWindow: Identifiable, Hashable, Sendable {
    let id: CGWindowID
    let title: String
    let processIdentifier: pid_t
    let frame: CGRect
    let isActive: Bool

    /// What to show in the sidebar. EVE titles look like "EVE - Character Name".
    var displayName: String {
        title.isEmpty ? "Untitled window #\(id)" : title
    }

    /// The character name, when the title follows EVE's "EVE - Name" convention.
    var characterName: String? {
        guard let range = title.range(of: " - ") else { return nil }
        let name = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    var sizeDescription: String {
        "\(Int(frame.width.rounded())) × \(Int(frame.height.rounded()))"
    }
}
