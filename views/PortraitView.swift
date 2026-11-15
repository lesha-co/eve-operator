import AppKit
import SwiftUI

struct PortraitView: View {

    let characterID = "94662640"
    let characterName = "Valeria Bessen"

    @State private var isHoveringName = false
    @State private var copied = false

    var body: some View {

        let esiURL = URL(
            string:
                "https://images.evetech.net/characters/\(characterID)/portrait?tenant=tranquility&size=128"
        )!
        LabeledContent("Support the developer") {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {

                    WordFlowLayout(spacing: Self.spaceWidth) {
                        ForEach(
                            Array(
                                "If you find EVE Operator useful and want to support me, send ISK to"
                                    .split(separator: " ").enumerated()), id: \.offset
                        ) {
                            _, word in
                            Text(word)
                        }
                        characterNameButton

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if copied {
                        
                        Label("Copied to clipboard. Thank you!", systemImage: "checkmark.circle.fill").secondaryCaption()
                        
                    }
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

    private var characterNameButton: some View {

        Button(action: copyCharacterName) {
            Text(characterName)
                .bold()
                .foregroundStyle(Color.accentColor)
                .underline(isHoveringName)
            
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering in
            isHoveringName = hovering
            if !hovering {
                copied = false
            }
        }
        .help("Copy the character name to the clipboard")
    }

    /// Width of a space in the body font, so the synthesized word gaps match
    /// the ones the text engine would have produced.
    private static var spaceWidth: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .body)
        return (" " as NSString).size(withAttributes: [.font: font]).width
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
