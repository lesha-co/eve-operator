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

    init(id: CGWindowID, title: String, processIdentifier: pid_t, frame: CGRect, isActive: Bool) {
        self.id = id
        self.title = title
        self.processIdentifier = processIdentifier
        self.frame = frame
        self.isActive = isActive
    }

    /// Label for the frame. EVE titles look like "EVE - Character Name"; a client only sets
    /// one once a character is in, so fall back to something that still identifies the client.
    var displayName: String {
        title.isEmpty ? "EVE (signing in\u{2026})" : title
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

    var aspectRatio: CGFloat {
        frame.height > 0 ? frame.width / frame.height : OverlayMetrics.fallbackAspectRatio
    }
}
