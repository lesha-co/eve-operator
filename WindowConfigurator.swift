//
//  WindowConfigurator.swift
//  eve-operator
//
//  Bridge for the handful of `NSWindow` properties SwiftUI does not expose.
//

import AppKit
import SwiftUI

/// Runs `configure` against the window hosting this view, and again whenever the enclosing
/// view updates — so a setting read inside `body` keeps the window in sync by itself.
///
/// The view draws nothing and is transparent to hit-testing, so it is safe to drop into a
/// `.background` without stealing clicks from whatever is really there.
struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSView) {
        if let window = view.window {
            configure(window)
        } else {
            // A view has no window until it has been installed in one.
            DispatchQueue.main.async {
                if let window = view.window { configure(window) }
            }
        }
    }
}

private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
