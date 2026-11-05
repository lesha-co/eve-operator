//
//  OverlayMetrics.swift
//  eve-operator
//
//  Every tuning constant in the app lives here: the defaults and legal ranges for the
//  user-editable settings, plus the fixed layout values that are not worth exposing.
//

import CoreGraphics

/// `nonisolated` so the constants can be used in default arguments and off the main actor.
nonisolated enum OverlayMetrics {

    // MARK: - Defaults for user-editable settings
    //
    // Each of these backs a property on `OverlaySettings`.

    /// Height of every screencast frame, in points.
    static let defaultFrameHeight: CGFloat = 100

    /// Frames past this many wrap onto the next row.
    static let defaultFramesPerRow: Int = 6

    /// Resting opacity of a frame, and the opacity it fades to while hovered.
    static let defaultIdleOpacity: Double = 0.75
    static let defaultHoverOpacity: Double = 1.0

    /// When false the strip is dragged by moving past `dragThreshold`; when true ⌘ is required.
    static let defaultRequiresCommandToDrag = false

    // MARK: - Legal ranges for those settings

    static let frameHeightRange: ClosedRange<CGFloat> = 40...300
    static let framesPerRowRange: ClosedRange<Int> = 1...12
    /// Never all the way to zero, or the strip becomes impossible to find again.
    static let opacityRange: ClosedRange<Double> = 0.05...1.0

    // MARK: - Fixed layout

    /// Frames stay between these proportions whatever shape the client's window really is,
    /// so one odd window can't stretch the strip across the screen.
    static let aspectRatioRange: ClosedRange<CGFloat> = 0.6...2.8

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

    /// With no clients to show, the strip collapses to nothing but its own padding.
    static var emptyStripHeight: CGFloat { padding * 2 }

    /// Status pills carry text, so they ignore the configured opacity once it drops too low.
    static let statusMinimumOpacity: Double = 0.55

    static let hoverAnimationDuration: Double = 0.12

    // MARK: - Helpers

    static func frameWidth(forAspectRatio ratio: CGFloat, height: CGFloat) -> CGFloat {
        let ratio = ratio.isFinite && ratio > 0 ? ratio : fallbackAspectRatio
        return (height * clamp(ratio, to: aspectRatioRange)).rounded()
    }

    static func statusOpacity(_ opacity: Double) -> Double {
        max(opacity, statusMinimumOpacity)
    }

    static func clamp<Value: Comparable>(_ value: Value, to range: ClosedRange<Value>) -> Value {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
