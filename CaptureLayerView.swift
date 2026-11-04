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

    func makeNSView(context: Context) -> CaptureHostView {
        let view = CaptureHostView()
        view.contentLayer = contentLayer
        return view
    }

    func updateNSView(_ nsView: CaptureHostView, context: Context) {
        nsView.contentLayer = contentLayer
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
        layer?.backgroundColor = NSColor.black.cgColor
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
