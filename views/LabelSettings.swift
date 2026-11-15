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
    
    var body: some View {
        Form {
            Section {
                LabeledContent("Default label color") {
                    ColorPicker(
                        "Default color", selection: $settings.labelColor, supportsOpacity: true
                    ).labelsHidden()
                }
                
                Text("Per-character colors can be set in the Characters tab").secondaryCaption()

                SliderRow(
                    title: "Label font size",
                    value: $settings.labelFontSize,
                    range: OverlayMetrics.labelFontSizeRange,
                    step: 1.0,
                    format: { "\(Int($0.rounded())) pt" })

                LabeledContent("Label position") {
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
}


#Preview("Labels") {
    Form {
        LabelSettings()
    }
    .scenePadding()
    .frame(width: 460)
}
