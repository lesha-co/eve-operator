//
//  OverlaySettings.swift
//  eve-operator
//
//  User-editable counterparts to the defaults in `OverlayMetrics`, persisted in UserDefaults.
//

import AppKit
import CoreGraphics
import Foundation
import Observation
import SwiftUI

/// Which edge of a frame the character name sits against.
nonisolated enum LabelEdge: String, CaseIterable, Identifiable {
    case top, bottom

    var id: String { rawValue }
    var title: String { self == .top ? "Top" : "Bottom" }
    var vertical: VerticalAlignment { self == .top ? .top : .bottom }
}

/// Where along that edge it sits.
nonisolated enum LabelAlignment: String, CaseIterable, Identifiable {
    case leading, center, trailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leading: return "Left"
        case .center: return "Middle"
        case .trailing: return "Right"
        }
    }

    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

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

    /// Point size of the character name drawn inside each frame.
    var labelFontSize: CGFloat {
        didSet { defaults.set(labelFontSize, forKey: Key.labelFontSize) }
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

    /// Whether the strip floats above other applications' windows.
    var previewsAlwaysOnTop: Bool {
        didSet { defaults.set(previewsAlwaysOnTop, forKey: Key.previewsAlwaysOnTop) }
    }

    /// Colour of the character name drawn inside each frame.
    var labelColor: Color {
        didSet { defaults.set(Self.hex(from: labelColor), forKey: Key.labelColor) }
    }

    var labelEdge: LabelEdge {
        didSet { defaults.set(labelEdge.rawValue, forKey: Key.labelEdge) }
    }

    var labelAlignment: LabelAlignment {
        didSet { defaults.set(labelAlignment.rawValue, forKey: Key.labelAlignment) }
    }

    /// Location of the EVE Online client bundle — see `EVEApplication`. Editable because the
    /// launcher's install directory is configurable, and because Singularity and other test
    /// shards sit beside `tq` in their own bundles.
    var eveBundlePath: String {
        didSet { defaults.set(eveBundlePath, forKey: Key.eveBundlePath) }
    }

    /// The two label settings as the single alignment the frame's `ZStack` needs.
    var labelPlacement: Alignment {
        Alignment(horizontal: labelAlignment.horizontal, vertical: labelEdge.vertical)
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
        previewsAlwaysOnTop =
            defaults.object(forKey: Key.previewsAlwaysOnTop) as? Bool
            ?? OverlayMetrics.defaultPreviewsAlwaysOnTop
        labelColor = Self.color(defaults, Key.labelColor, or: OverlayMetrics.defaultLabelColor)
        labelEdge = Self.option(
            defaults, Key.labelEdge, or: OverlayMetrics.defaultLabelEdge)
        labelAlignment = Self.option(
            defaults, Key.labelAlignment, or: OverlayMetrics.defaultLabelAlignment)
        labelFontSize = Self.double(
            defaults, Key.labelFontSize,
            or: OverlayMetrics.defaultLabelFontSize,
            in:
                Double(
                    OverlayMetrics.labelFontSizeRange.lowerBound)...Double(
                    OverlayMetrics.labelFontSizeRange.upperBound))
        eveBundlePath = Self.path(
            defaults, Key.eveBundlePath, or: OverlayMetrics.defaultEVEBundlePath)
    }

    func resetToDefaults() {
        idleOpacity = OverlayMetrics.defaultIdleOpacity
        hoverOpacity = OverlayMetrics.defaultHoverOpacity
        frameHeight = OverlayMetrics.defaultFrameHeight
        framesPerRow = OverlayMetrics.defaultFramesPerRow
        requiresCommandToDrag = OverlayMetrics.defaultRequiresCommandToDrag
        previewsAlwaysOnTop = OverlayMetrics.defaultPreviewsAlwaysOnTop
        labelColor = OverlayMetrics.defaultLabelColor
        labelEdge = OverlayMetrics.defaultLabelEdge
        labelAlignment = OverlayMetrics.defaultLabelAlignment
        labelFontSize = OverlayMetrics.defaultLabelFontSize
        eveBundlePath = OverlayMetrics.defaultEVEBundlePath
    }

    var isDefault: Bool {
        idleOpacity == OverlayMetrics.defaultIdleOpacity
            && hoverOpacity == OverlayMetrics.defaultHoverOpacity
            && frameHeight == OverlayMetrics.defaultFrameHeight
            && framesPerRow == OverlayMetrics.defaultFramesPerRow
            && requiresCommandToDrag == OverlayMetrics.defaultRequiresCommandToDrag
            && previewsAlwaysOnTop == OverlayMetrics.defaultPreviewsAlwaysOnTop
            && labelEdge == OverlayMetrics.defaultLabelEdge
            && labelAlignment == OverlayMetrics.defaultLabelAlignment
            && labelFontSize == OverlayMetrics.defaultLabelFontSize
            && eveBundlePath == OverlayMetrics.defaultEVEBundlePath
            // Compared through the stored form: a colour round-tripped via sRGB is never
            // `==` to the catalogue colour it came from, even when it looks identical.
            && Self.hex(from: labelColor) == Self.hex(from: OverlayMetrics.defaultLabelColor)
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

    /// A blank path would make `EVEApplication` look for the client at the root of the disk,
    /// so it is treated as "unset". Tildes are expanded on the way in: the stored form stays
    /// portable between home directories, and everything downstream gets a usable path.
    private static func path(_ defaults: UserDefaults, _ key: String, or fallback: String) -> String
    {
        guard let raw = defaults.string(forKey: key) else { return fallback }
        let expanded = (raw as NSString).expandingTildeInPath
        return expanded.isEmpty ? fallback : expanded
    }

    private static func option<Option: RawRepresentable>(
        _ defaults: UserDefaults, _ key: String, or fallback: Option
    ) -> Option where Option.RawValue == String {
        guard let raw = defaults.string(forKey: key), let value = Option(rawValue: raw) else {
            return fallback
        }
        return value
    }

    // MARK: - Colour storage

    /// Written as #RRGGBBAA so the plist stays legible and survives a colour-space change.
    private static func hex(from color: Color) -> String {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return "#FFFFFFFF" }
        let channels = [
            srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent,
        ]
        return channels.reduce(into: "#") { hex, channel in
            hex += String(
                format: "%02X", Int((OverlayMetrics.clamp(channel, to: 0...1) * 255).rounded()))
        }
    }

    private static func color(_ defaults: UserDefaults, _ key: String, or fallback: Color) -> Color
    {
        guard var raw = defaults.string(forKey: key) else { return fallback }
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 8, let packed = UInt32(raw, radix: 16) else { return fallback }
        return Color(
            .sRGB,
            red: Double((packed >> 24) & 0xFF) / 255,
            green: Double((packed >> 16) & 0xFF) / 255,
            blue: Double((packed >> 8) & 0xFF) / 255,
            opacity: Double(packed & 0xFF) / 255)
    }

    private enum Key {
        static let idleOpacity = "overlay.idleOpacity"
        static let hoverOpacity = "overlay.hoverOpacity"
        static let frameHeight = "overlay.frameHeight"
        static let labelFontSize = "overlay.labelFontSize"
        static let framesPerRow = "overlay.framesPerRow"
        static let requiresCommandToDrag = "overlay.requiresCommandToDrag"
        static let previewsAlwaysOnTop = "overlay.previewsAlwaysOnTop"
        static let labelColor = "overlay.labelColor"
        static let labelEdge = "overlay.labelEdge"
        static let labelAlignment = "overlay.labelAlignment"
        static let eveBundlePath = "eve.bundlePath"
    }
}
