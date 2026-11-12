//
//  OverlayMetrics.swift
//  eve-operator
//
//  Every tuning constant in the app lives here: the defaults and legal ranges for the
//  user-editable settings, plus the fixed layout values that are not worth exposing.
//

import CoreGraphics
import Foundation
import SwiftUI

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

    /// Whether the strip floats above other applications' windows.
    static let defaultPreviewsAlwaysOnTop = true

    /// Whether the frontmost client's preview is picked out with a coloured border.
    static let defaultHighlightsActiveClient = true

    /// Whether the status item is in the menu bar.
    static let defaultShowsMenuBarIcon = true

    /// Colour of the character name drawn inside a frame, and where in the frame it sits.
    static let defaultLabelColor = Color.white
    static let defaultLabelEdge = LabelEdge.bottom
    static let defaultLabelAlignment = LabelAlignment.leading
    /// Character name shown inside a frame.
    static let defaultLabelFontSize: CGFloat = 9

    /// Whether F1…F12 raise the preview in that position, and the modifiers they are
    /// qualified with. No modifier by default: the keys are worth taking from EVE, which is
    /// what `defaultHotKeysOnlyWhileClientActive` confines the theft to.
    static let defaultHotKeysEnabled = true
    static let defaultHotKeyModifiers: HotKeyModifiers = []
    static let defaultHotKeysOnlyWhileClientActive = true

    /// Whether the frame's label is prefixed with the key that raises it.
    static let defaultShowsHotKeyInLabel = false

    /// Where the EVE Online launcher puts the Tranquility client.
    static let defaultEVEBundlePath =
        ("~/Library/Application Support/EVE Online/SharedCache/tq/EVE.app" as NSString)
        .expandingTildeInPath

    /// Empty means "not configured". The app autodetects once on first launch rather than
    /// shipping a guess, because the folder's name is derived from wherever EVE was installed.
    static let defaultEVESettingsFolderPath = ""

    /// The profile EVE creates on a fresh install. Nothing on disk records which one the
    /// client is actually using, so this is a starting point and not a reading.
    static let defaultEVESettingsProfile = EVESettingsLocation.defaultProfile

    /// Which of a custom EVE theme's four colours a mirrored label takes — see
    /// `docs/eve-settings-files.md` §6. Fixed rather than chosen: `tint` is commonly
    /// `#ff000000` and would be invisible on a dark preview, and the other two are not worth
    /// a dial. The name is the key EVE writes inside a theme object.
    static let defaultMirroredThemeChannel = "focus"

    // MARK: - Legal ranges for those settings

    static let frameHeightRange: ClosedRange<CGFloat> = 40...300
    static let framesPerRowRange: ClosedRange<Int> = 1...6
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

    /// Gap between a docked strip and the edges of the usable screen. The centre docks are
    /// only inset on the axis they are not centred on.
    static let dockInset: CGFloat = 0

    /// Dropping the strip with its leading-bottom corner this close — on both axes — to where
    /// a dock would put it counts as aiming for that dock. Generous, because the whole point
    /// is not having to be accurate.
    static let dockSnapDistance: CGFloat = 240

    /// How long the strip takes to ease into a dock it was dropped near.
    static let dockEaseDuration: Double = 0.16

    /// How far the pointer has to travel before a press counts as a drag rather than a click.
    static let dragThreshold: CGFloat = 4

    static let labelFontSizeRange: ClosedRange<CGFloat> = 8.0...20.0

    /// Status pills wrap instead of stretching the strip.
    static let statusMaxWidth: CGFloat = 220

    /// With no clients to show, the strip collapses to nothing but its own padding.
    static var emptyStripHeight: CGFloat { padding * 2 }

    /// Status pills carry text, so they ignore the configured opacity once it drops too low.
    static let statusMinimumOpacity: Double = 0.55

    /// Labels carry text too, and the same bargain applies — except a caption over a busy
    /// client is harder to read than a pill on its own dark background, so the floor sits
    /// much higher. High enough to read as opaque, low enough that the hover fade still
    /// shows.
    static let labelMinimumOpacity: Double = 0.9

    static let hoverAnimationDuration: Double = 0.12

    // MARK: - Frame border

    static let activeBorderWidth: CGFloat = 5

    // MARK: - Helpers

    static func frameWidth(forAspectRatio ratio: CGFloat, height: CGFloat) -> CGFloat {
        let ratio = ratio.isFinite && ratio > 0 ? ratio : fallbackAspectRatio
        return (height * clamp(ratio, to: aspectRatioRange)).rounded()
    }

    static func statusOpacity(_ opacity: Double) -> Double {
        max(opacity, statusMinimumOpacity)
    }

    static func labelOpacity(_ opacity: Double) -> Double {
        max(opacity, labelMinimumOpacity)
    }

    static func clamp<Value: Comparable>(_ value: Value, to range: ClosedRange<Value>) -> Value {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
