//
//  CaptureLayerView.swift
//  eve-operator
//
//  Hosts the capture session's CALayer so frames bypass SwiftUI's render loop.
//

import AppKit
import SwiftUI

struct CaptureLayerView: NSViewRepresentable {
    let contentLayer: CALayer
    /// Applied to the capture layer itself. SwiftUI's `.opacity` does not reach an
    /// `NSViewRepresentable`, and it resets the hosted view's `alphaValue` during layout,
    /// so the only stable place to set this is the layer we own.
    var opacity: Double = 1
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> CaptureHostView {
        let view = CaptureHostView()
        view.contentLayer = contentLayer
        apply(to: view, animated: false)
        return view
    }

    func updateNSView(_ nsView: CaptureHostView, context: Context) {
        nsView.contentLayer = contentLayer
        apply(to: nsView, animated: true)
    }

    private func apply(to view: CaptureHostView, animated: Bool) {
        view.layer?.cornerRadius = cornerRadius

        let target = Float(opacity)
        guard abs(contentLayer.opacity - target) > 0.001 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated ? 0.12 : 0)
        contentLayer.opacity = target
        CATransaction.commit()
    }
}

final class CaptureHostView: NSView {

    var contentLayer: CALayer? {
        didSet {
            guard contentLayer !== oldValue else { return }
            oldValue?.removeFromSuperlayer()
            if let contentLayer {
                layer?.addSublayer(contentLayer)
                needsLayout = true
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer?.frame = bounds
        CATransaction.commit()
    }
}
