//
//  EVEWindow.swift
//  eve-operator
//
//  A value-type snapshot of one on-screen EVE client window.
//

import CoreGraphics
import Foundation
import ScreenCaptureKit

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

    init(_ window: SCWindow, frontmostProcess: pid_t?) {
        let pid = window.owningApplication?.processID ?? -1
        self.init(
            id: window.windowID,
            title: window.title ?? "",
            processIdentifier: pid,
            frame: window.frame,
            isActive: pid == frontmostProcess)
    }

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

    var aspectRatio: CGFloat {
        frame.height > 0 ? frame.width / frame.height : OverlayMetrics.fallbackAspectRatio
    }
}
