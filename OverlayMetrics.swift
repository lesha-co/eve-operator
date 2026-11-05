//
//  OverlayMetrics.swift
//  eve-operator
//
//  Sizing and opacity constants for the floating overlay strip.
//

import CoreGraphics

/// `nonisolated` so the constants can be used in default arguments and off the main actor.
nonisolated enum OverlayMetrics {
    /// Height of every screencast frame, in points.
    static let frameHeight: CGFloat = 100

    /// Frames narrower/wider than this look wrong next to their neighbours.
    static let frameWidthRange: ClosedRange<CGFloat> = 60...280

    /// Fallback aspect ratio used before a window's real geometry is known.
    static let fallbackAspectRatio: CGFloat = 16.0 / 10.0

    static let spacing: CGFloat = 6
    static let padding: CGFloat = 6
    static let cornerRadius: CGFloat = 5

    /// Distance from the top of the screen when the strip has no remembered position.
    static let defaultTopInset: CGFloat = 8

    /// How far the pointer has to travel before a press counts as a drag rather than a click.
    static let dragThreshold: CGFloat = 4

    /// Character name shown inside a frame.
    static let labelFontSize: CGFloat = 9

    /// Status pills wrap instead of stretching the strip.
    static let statusMaxWidth: CGFloat = 220

    static let hoverAnimationDuration: Double = 0.12

    /// Resting opacity of a frame, and the opacity it fades to while hovered.
    static let idleOpacity: Double = 0.4
    static let hoverOpacity: Double = 1.0

    /// The status pill has to stay readable, so it uses its own, higher range.
    static let statusIdleOpacity: Double = 0.55
    static let statusHoverOpacity: Double = 0.95

    static func frameWidth(forAspectRatio ratio: CGFloat) -> CGFloat {
        let ratio = ratio.isFinite && ratio > 0 ? ratio : fallbackAspectRatio
        return min(max(frameHeight * ratio, frameWidthRange.lowerBound), frameWidthRange.upperBound)
    }
}
