//
//  StripSettings.swift
//  eve-operator
//
//  Created by lesha on 15. 11. 2026..
//

import SwiftUI

// MARK: - Tabs

struct StripSettings: View {
    
    @Bindable private var settings = OverlaySettings.shared
    
    var body: some View {
        
        Form {
            
            SliderRow(
                title: "Default opacity",
                value: $settings.idleOpacity,
                range: OverlayMetrics.opacityRange,
                format: percent)
            
            SliderRow(
                title: "Focused opacity",
                value: $settings.hoverOpacity,
                range: OverlayMetrics.opacityRange,
                format: percent)
            
            SliderRow(
                title: "Frame height",
                value: $settings.frameHeight,
                range: OverlayMetrics.frameHeightRange,
                step: 10.0,
                format: { "\(Int($0.rounded())) pt" })
            
            HStack{
                Picker("Frames in a row", selection: $settings.framesPerRow) {
                    ForEach(OverlayMetrics.framesPerRowRange, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            
            Toggle("Previews always on top", isOn: $settings.previewsAlwaysOnTop)
            
            FullWidthDivider()

            
            Picker("Active client", selection: $settings.activeClientMark) {
                ForEach(ActiveClientMark.allCases) { mark in
                    VStack(alignment: .leading) {
                        Text(mark.title)
                        Text(mark.description).secondaryCaption()
                    }
                    .tag(mark)
                }
            }
            .pickerStyle(.radioGroup)

            

            
            

            FullWidthDivider()
            
            LabeledContent("Dragging") {
                Picker("Drag", selection: $settings.requiresCommandToDrag) {
                    VStack(alignment: .leading) {
                        Text("Drag from anywhere")
                        Text(
                            "A press that travels more than \(Int(OverlayMetrics.dragThreshold)) pt moves the strip; anything shorter raises the client under the pointer."
                        ).secondaryCaption()
                    }
                    .tag(false)
                    VStack(alignment: .leading) {
                        Text("Hold ⌘ to drag")
                        Text(
                            "A plain click always raises the client under the pointer. Hold ⌘ and drag to move the strip."
                        ).secondaryCaption()
                    }
                    .tag(true)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            
            FullWidthDivider()
            
            PortraitView()
        }
        .clipped()
    }
    
    private nonisolated func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}



#Preview {
    Form {
        StripSettings()
    }
    .scenePadding()
    .frame(width: 460)
}
