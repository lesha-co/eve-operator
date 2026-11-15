import AppKit
import SwiftUI

let characterID = "94662640"
let characterName = "Valeria Bessen"

struct PortraitView: View {
    
    var body: some View {

        let esiURL = URL(
            string:
                "https://images.evetech.net/characters/\(characterID)/portrait?tenant=tranquility&size=128"
        )!
        LabeledContent("Support & Feedback") {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {

                    Text("If you find EVE Operator useful and want to support me, send ISK to **\(characterName)**. If your donation includes the words \"**eve operator**\" i will send you an eve mail whenever an update comes out.")
                    
                    CopyButton()
                    
                    Text("Oh and by the way if you have any feedback you can reach me ")
                    
                }
                AsyncImage(url: esiURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            }
        }

    }

    
}

private struct CopyButton: View {
    
    @State private var isHoveringName = false
    @State private var copied = false
    var body: some View {
            Button(action: copyCharacterName) {
                Label("Copy name to the clipboard", systemImage: copied ? "checkmark.circle.fill":"document.on.document")
            }
            .buttonStyle(.borderedProminent)
            .onHover { hovering in
                if !hovering {
                    copied = false
                }
            }
            
        }
        
        private func copyCharacterName() {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(characterName, forType: .string)
            copied = true
        }
    
}

private struct WordFlowLayout: Layout {

    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGSize {
        arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) {
        let origins = arrange(subviews: subviews, maxWidth: bounds.width).origins
        for (subview, origin) in zip(subviews, origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(
        subviews: Subviews, maxWidth: CGFloat
    ) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            width = max(width, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: width, height: y + lineHeight), origins)
    }
}

#Preview {
    Form {
        PortraitView()
    }
    .scenePadding()
    .frame(width: 460)
}
