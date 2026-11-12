import SwiftUI

extension View {
    /// The look every explanatory note in the settings windows shares: small type, dimmed so
    /// it reads as commentary next to the control it belongs to.
    ///
    /// Applied to a container rather than a single `Text` it styles the whole subtree, which
    /// is what the mixed text-and-link notices want.
    func secondaryCaption() -> some View {
        font(.caption).foregroundStyle(.secondary)
    }
}
