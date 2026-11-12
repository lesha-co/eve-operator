//
//  LabelSettings.swift
//  eve-operator
//
//  The Labels tab of the Settings scene: how a preview's caption is drawn, and where each
//  character's colour comes from — the default, a fixed one, or the character's own in-game
//  EVE UI theme.
//

import SwiftUI

struct LabelSettings: View {

    @Bindable private var settings = OverlaySettings.shared

    private var roster = CharacterRoster.shared
    private var themes = EVEThemeStore.shared

    var body: some View {
        Form {
            Section {

                LabeledContent("Default color") {
                    ColorPicker(
                        "Default color", selection: $settings.labelColor, supportsOpacity: true
                    ).labelsHidden()
                }

                LabeledContent("Per-character") {
                    perCharacter
                }

                FullWidthDivider()
                SliderRow(
                    title: "Font size",
                    value: $settings.labelFontSize,
                    range: OverlayMetrics.labelFontSizeRange,
                    step: 1.0,
                    format: { "\(Int($0.rounded())) pt" })

                LabeledContent("Position") {
                    VStack(spacing: 6) {
                        Picker("Edge", selection: $settings.labelEdge) {
                            ForEach(LabelEdge.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Alignment", selection: $settings.labelAlignment) {
                            ForEach(LabelAlignment.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

            }
        }
        .clipped()
    }

    @ViewBuilder private var perCharacter: some View {
        VStack(alignment: .leading) {
            if roster.characters.isEmpty {
                Text("No characters seen yet. Log a client in and it will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                rosterTable
            }

            HStack {
                Button("Set to mirror") {
                    for entry in roster.characters {
                        settings.setLabelColor(.mirrored, for: entry.name)
                    }
                }
                Button("Set to default") { settings.clearCharacterLabelColors() }
                    .disabled(settings.characterLabelColors.isEmpty)

                // The only thing that re-reads EVE's folder after launch. Deliberate: the files
                // change at most once per logout, so watching for it costs more than a click.
                Button("Reload colors") { themes.reload() }
                    .disabled(themes.status == .loading)

            }
            readStatus
        }

    }

    private var rosterTable: some View {
        Table(roster.characters) {
            TableColumn("Character") { CharacterNameCell(entry: $0) }
            TableColumn("Color") { CharacterColorCell(entry: $0) }
                .width(min: 50, ideal: 50, max: 50)
            TableColumn("Source") { CharacterSourceCell(entry: $0) }
                .width(min: 64, ideal: 64, max: 64)
        }
        .tableStyle(.bordered)
        .alternatingRowBackgrounds()

        .environment(\.defaultMinListRowHeight, RosterTable.cell)
        .frame(height: tableHeight)
        // A `Table` publishes no text baseline. Without this the enclosing stack has none
        // to report either, and the row's `.firstTextBaseline` alignment falls back to the
        // content's top edge — which then gets parked on the label's baseline, dropping the
        // whole block a line below "Per-character". Offer the header's baseline instead.
        .alignmentGuide(.firstTextBaseline) { $0[.top] + RosterTable.headerBaseline }
    }

    /// A `Table` has no intrinsic height and the settings tabs size themselves to their
    /// content, so an unpinned one either collapses or pushes the window off the screen.
    private var tableHeight: CGFloat {
        let visible = min(max(roster.characters.count, 5), 8)
        return CGFloat(visible) * RosterTable.row + RosterTable.header
    }

    @ViewBuilder private var readStatus: some View {
        switch themes.status {
        case .notConfigured:
            Text("Settings folder not set")
                .font(.caption)
                .foregroundStyle(.orange)
        case .loading:
            Text("Reading\u{2026}").font(.caption).foregroundStyle(.secondary)
        case .ok:
            EmptyView()
        case .failed(let reason):
            Text(reason)
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Roster table cells

/// A `Table` takes its row height from the tallest cell, so the cells are pinned small and
/// the frame above is sized from the same numbers. Default sizing leaves each row about a
/// third taller than the controls in it.
private enum RosterTable {
    /// What one row occupies, cell plus the table's own vertical padding.
    static let row: CGFloat = 20
    static let header: CGFloat = 24
    /// Where the header's text sits, measured from the top of the table. Only used to line
    /// the Form label up with it.
    static let headerBaseline: CGFloat = 18
    /// Enough for a small color well and a small pop-up button, and no more.
    static let cell: CGFloat = 16
}

/// The three cells below are one logical row, split because a `Table` addresses columns
/// rather than rows. Each reads the stores it needs directly, so a change to one character's
/// colour redraws that cell and nothing else.

private struct CharacterNameCell: View {

    let entry: CharacterRoster.Entry

    var body: some View {
        HStack(spacing: 5) {
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.tail)
            if entry.isOnline {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.green)
                    .help("Logged in now")
            }
        }
        .font(.callout)
        .frame(height: RosterTable.cell, alignment: .leading)
    }
}

/// What this character's label is drawn in, and — when it is a colour of its own — the way
/// to change it.
private struct CharacterColorCell: View {

    let entry: CharacterRoster.Entry

    // Spelled out because the private stores below make the memberwise one private too.
    init(entry: CharacterRoster.Entry) { self.entry = entry }

    @Bindable private var settings = OverlaySettings.shared
    private var themes = EVEThemeStore.shared
    private var roster = CharacterRoster.shared

    var body: some View {
        content
            .controlSize(.small)
            .frame(height: RosterTable.cell, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
        switch settings.labelColorSetting(for: entry.name) {
        case .inherited:
            // Shown, not offered: editing it here would move the default out from under
            // every other inherited row. The Default color picker above owns it.
            swatch(settings.labelColor, help: "Default color")
        case .fixed:
            ColorPicker("Color", selection: customColor, supportsOpacity: false)
                .labelsHidden()
        case .mirrored:
            if entry.characterID == nil {
                assignMenu
            } else {
                mirrorResult
            }
        }
    }

    /// A colour this row displays but does not own — the global default, or one mirrored out
    /// of EVE. Rendered as a picker so it lines up with the editable rows, inert because the
    /// value belongs somewhere else.
    private func swatch(_ color: Color, help: String) -> some View {
        ColorPicker("Color", selection: .constant(color), supportsOpacity: false)
            .labelsHidden()
            .disabled(true)
            .help(help)
    }

    @ViewBuilder private var mirrorResult: some View {
        let resolution = LabelColors.resolve(entry.name)
        switch resolution.source {
        case .mirrored(let hex):
            swatch(resolution.color, help: hex)
        case .unavailable(let reason):
            // The column is too narrow for the sentence, so the swatch shows what is
            // actually being drawn and the warning carries the reason.
            HStack(spacing: 3) {
                swatch(resolution.color, help: "\(reason) \u{2014} using default")
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("\(reason) \u{2014} using default")
            }
        case .global, .custom:
            EmptyView()
        }
    }

    /// ESI could not say which ID this name belongs to, so offer the IDs the settings folder
    /// knows about and let the user settle it.
    @ViewBuilder private var assignMenu: some View {
        if themes.knownCharacterIDs.isEmpty {
            Text("no IDs").foregroundStyle(.secondary).help(
                "The settings folder holds no character files")
        } else {
            Menu("Assign\u{2026}") {
                ForEach(themes.knownCharacterIDs, id: \.self) { id in
                    Button("\(id)") { roster.assign(id: id, to: entry.name) }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(resolutionHelp)
        }
    }

    private var resolutionHelp: String {
        if case .failed(let reason) = entry.resolution {
            return "Could not look this name up: \(reason)"
        }
        return "This character's ID is not known yet"
    }

    private var customColor: Binding<Color> {
        Binding(
            get: {
                if case .fixed(let color) = settings.labelColorSetting(for: entry.name) {
                    return color
                }
                return settings.labelColor
            },
            set: { settings.setLabelColor(.fixed($0), for: entry.name) })
    }
}

/// Where this character's colour comes from.
private struct CharacterSourceCell: View {

    let entry: CharacterRoster.Entry

    init(entry: CharacterRoster.Entry) { self.entry = entry }

    @Bindable private var settings = OverlaySettings.shared
    private var roster = CharacterRoster.shared

    private enum Source: String, CaseIterable, Identifiable {
        case inherited, mirrored, custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .inherited: return "Default"
            case .mirrored: return "Mirror"
            case .custom: return "Custom"
            }
        }
    }

    var body: some View {
        Picker("Source", selection: source) {
            ForEach(Source.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .controlSize(.small)
        // Height first, then width: the inner frame pins the row metric and passes the
        // column's full width through, so the pop-up fills its cell instead of hugging the
        // longest title.
        .frame(height: RosterTable.cell)
        .frame(maxWidth: .infinity)
    }

    private var source: Binding<Source> {
        Binding(
            get: {
                switch settings.labelColorSetting(for: entry.name) {
                case .inherited: return .inherited
                case .mirrored: return .mirrored
                case .fixed: return .custom
                }
            },
            set: { new in
                switch new {
                case .inherited:
                    settings.setLabelColor(.inherited, for: entry.name)
                case .mirrored:
                    settings.setLabelColor(.mirrored, for: entry.name)
                    // A name with no ID has nothing to mirror from; asking now means the row
                    // can offer a result rather than a shrug.
                    if entry.characterID == nil { roster.resolvePending() }
                case .custom:
                    // Seeded with whatever the row resolves to today, so "mirror, then
                    // tweak" starts from the mirrored colour rather than from white.
                    settings.setLabelColor(
                        .fixed(LabelColors.resolve(entry.name).color), for: entry.name)
                }
            })
    }
}

#Preview("Labels") {
    Form {
        LabelSettings()
    }
    .labeledContentStyle(.boldLabel)
    .scenePadding()
    .frame(width: 460)
}
