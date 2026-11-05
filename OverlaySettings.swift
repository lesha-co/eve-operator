//
//  OverlaySettings.swift
//  eve-operator
//
//  User-editable counterparts to the defaults in `OverlayMetrics`, persisted in UserDefaults.
//

import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class OverlaySettings {

    /// The overlay panel, the strip and the settings pane all read the same instance.
    static let shared = OverlaySettings()

    /// Resting opacity of a frame.
    var idleOpacity: Double {
        didSet { defaults.set(idleOpacity, forKey: Key.idleOpacity) }
    }

    /// Opacity a frame fades to while the pointer is over it.
    var hoverOpacity: Double {
        didSet { defaults.set(hoverOpacity, forKey: Key.hoverOpacity) }
    }

    /// Height of every screencast frame, in points. Widths follow from each window's shape.
    var frameHeight: CGFloat {
        didSet { defaults.set(Double(frameHeight), forKey: Key.frameHeight) }
    }

    /// Frames past this many wrap onto the next row.
    var framesPerRow: Int {
        didSet { defaults.set(framesPerRow, forKey: Key.framesPerRow) }
    }

    /// When true the strip only moves while ⌘ is held, so a slip of the hand can't nudge it
    /// out from under the pointer. When false any press that travels past
    /// `OverlayMetrics.dragThreshold` starts a drag.
    var requiresCommandToDrag: Bool {
        didSet { defaults.set(requiresCommandToDrag, forKey: Key.requiresCommandToDrag) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        idleOpacity = Self.double(
            defaults, Key.idleOpacity,
            or: OverlayMetrics.defaultIdleOpacity, in: OverlayMetrics.opacityRange)
        hoverOpacity = Self.double(
            defaults, Key.hoverOpacity,
            or: OverlayMetrics.defaultHoverOpacity, in: OverlayMetrics.opacityRange)
        frameHeight = CGFloat(
            Self.double(
                defaults, Key.frameHeight,
                or: Double(OverlayMetrics.defaultFrameHeight),
                in: Double(
                    OverlayMetrics.frameHeightRange.lowerBound)...Double(
                        OverlayMetrics.frameHeightRange.upperBound)))
        framesPerRow = Self.integer(
            defaults, Key.framesPerRow,
            or: OverlayMetrics.defaultFramesPerRow, in: OverlayMetrics.framesPerRowRange)
        requiresCommandToDrag =
            defaults.object(forKey: Key.requiresCommandToDrag) as? Bool
            ?? OverlayMetrics.defaultRequiresCommandToDrag
    }

    func resetToDefaults() {
        idleOpacity = OverlayMetrics.defaultIdleOpacity
        hoverOpacity = OverlayMetrics.defaultHoverOpacity
        frameHeight = OverlayMetrics.defaultFrameHeight
        framesPerRow = OverlayMetrics.defaultFramesPerRow
        requiresCommandToDrag = OverlayMetrics.defaultRequiresCommandToDrag
    }

    var isDefault: Bool {
        idleOpacity == OverlayMetrics.defaultIdleOpacity
            && hoverOpacity == OverlayMetrics.defaultHoverOpacity
            && frameHeight == OverlayMetrics.defaultFrameHeight
            && framesPerRow == OverlayMetrics.defaultFramesPerRow
            && requiresCommandToDrag == OverlayMetrics.defaultRequiresCommandToDrag
    }

    // MARK: - Reading

    /// A plist written by an older build — or by hand — can hold anything, so every value is
    /// clamped to the range the settings pane would have allowed.
    private static func double(
        _ defaults: UserDefaults, _ key: String, or fallback: Double, in range: ClosedRange<Double>
    ) -> Double {
        guard let value = defaults.object(forKey: key) as? Double, value.isFinite else {
            return fallback
        }
        return OverlayMetrics.clamp(value, to: range)
    }

    private static func integer(
        _ defaults: UserDefaults, _ key: String, or fallback: Int, in range: ClosedRange<Int>
    ) -> Int {
        guard let value = defaults.object(forKey: key) as? Int else { return fallback }
        return OverlayMetrics.clamp(value, to: range)
    }

    private enum Key {
        static let idleOpacity = "overlay.idleOpacity"
        static let hoverOpacity = "overlay.hoverOpacity"
        static let frameHeight = "overlay.frameHeight"
        static let framesPerRow = "overlay.framesPerRow"
        static let requiresCommandToDrag = "overlay.requiresCommandToDrag"
    }
}
