//
//  WindowCaptureSession.swift
//  eve-operator
//
//  Live ScreenCaptureKit stream of a single window, rendered into a CALayer.
//

import AppKit
import CoreMedia
import CoreVideo
import IOSurface
import ScreenCaptureKit

/// A frame handed from the capture queue to the main actor.
/// `IOSurfaceRef` is not `Sendable`, but ownership is transferred and never mutated here.
struct CapturedFrame: @unchecked Sendable {
    let surface: IOSurfaceRef
    let size: CGSize
}

@MainActor
@Observable
final class WindowCaptureSession {

    enum State: Equatable {
        case idle
        case starting
        case streaming
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var windowID: CGWindowID?
    /// Size of the frames currently being delivered, in pixels.
    private(set) var frameSize: CGSize = .zero

    /// Frames are written straight into this layer instead of through SwiftUI state.
    @ObservationIgnored
    let layer: CALayer = {
        let layer = CALayer()
        layer.contentsGravity = .resizeAspect
        layer.backgroundColor = NSColor.clear.cgColor
        layer.isOpaque = false
        return layer
    }()

    /// Frames are only ever shown this tall, so there is no point streaming more pixels.
    @ObservationIgnored private let preferredHeight: CGFloat
    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var forwarder: FrameForwarder?
    @ObservationIgnored private var capturedFrame: CGRect = .zero
    @ObservationIgnored private let outputQueue = DispatchQueue(
        label: "co.lesha.eve-operator.capture", qos: .userInitiated)

    init(preferredHeight: CGFloat = OverlayMetrics.frameHeight) {
        self.preferredHeight = preferredHeight
    }

    // MARK: - Lifecycle

    /// Starts capturing `window`, unless it is already the window being captured.
    func start(window: SCWindow) async {
        guard windowID != window.windowID else { return }
        await restart(window: window)
    }

    func restart(window: SCWindow) async {
        await stop()
        windowID = window.windowID
        state = .starting

        do {
            let configuration = self.configuration(forSize: window.frame.size)
            let filter = SCContentFilter(desktopIndependentWindow: window)

            let forwarder = FrameForwarder(
                onFrame: { [weak self] frame in
                    Task { @MainActor [weak self] in self?.present(frame) }
                },
                onStop: { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.state = .failed(error.localizedDescription)
                    }
                })

            let stream = SCStream(filter: filter, configuration: configuration, delegate: forwarder)
            try stream.addStreamOutput(forwarder, type: .screen, sampleHandlerQueue: outputQueue)
            try await stream.startCapture()

            self.stream = stream
            self.forwarder = forwarder
            self.capturedFrame = window.frame
            self.state = .streaming
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    /// Convenience for callers that only hold a window id.
    func start(windowID id: CGWindowID) async {
        guard windowID != id else { return }
        guard let window = try? await WindowDiscovery.shareableWindow(id: id) else {
            state = .failed("That window is no longer available.")
            return
        }
        await restart(window: window)
    }

    func stop() async {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        forwarder = nil
        windowID = nil
        capturedFrame = .zero
        frameSize = .zero
        state = .idle
        setContents(nil)
    }

    /// Re-configures the stream when the captured window has been resized.
    func adapt(to window: EVEWindow) async {
        guard windowID == window.id, let stream, state == .streaming else { return }
        let old = capturedFrame.size
        let new = window.frame.size
        guard abs(old.width - new.width) > 1 || abs(old.height - new.height) > 1 else { return }

        capturedFrame = window.frame
        let configuration = self.configuration(forSize: new)
        try? await stream.updateConfiguration(configuration)
    }

    // MARK: - Frame presentation

    private func present(_ frame: CapturedFrame) {
        if state != .streaming { state = .streaming }
        frameSize = frame.size
        setContents(frame.surface)
    }

    private func setContents(_ contents: Any?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = contents
        CATransaction.commit()
    }

    // MARK: - Helpers

    /// Streams at the on-screen thumbnail size rather than the window's native size, so a
    /// dozen simultaneous clients stay cheap.
    private func configuration(forSize size: CGSize) -> SCStreamConfiguration {
        let backingScale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let aspectRatio =
            size.height > 0 ? size.width / size.height : OverlayMetrics.fallbackAspectRatio
        let height = min(size.height, preferredHeight) * backingScale

        let configuration = SCStreamConfiguration()
        configuration.width = max(2, Int((height * aspectRatio).rounded()))
        configuration.height = max(2, Int(height.rounded()))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 20)
        configuration.queueDepth = 3
        configuration.showsCursor = true
        configuration.scalesToFit = true
        configuration.capturesAudio = false
        return configuration
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain,
            nsError.code == SCStreamError.userDeclined.rawValue
        {
            return "Screen Recording permission was declined."
        }
        return error.localizedDescription
    }
}

// MARK: - Stream output

/// Receives sample buffers off the main actor and hands the backing IOSurface to the session.
private nonisolated final class FrameForwarder: NSObject, SCStreamOutput, SCStreamDelegate {

    private let onFrame: @Sendable (CapturedFrame) -> Void
    private let onStop: @Sendable (Error) -> Void

    init(
        onFrame: @escaping @Sendable (CapturedFrame) -> Void,
        onStop: @escaping @Sendable (Error) -> Void
    ) {
        self.onFrame = onFrame
        self.onStop = onStop
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid else { return }

        // Skip idle/blank frames so the last good frame stays on screen.
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int,
            SCFrameStatus(rawValue: rawStatus) == .complete,
            let pixelBuffer = sampleBuffer.imageBuffer,
            let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }

        let size = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer))
        onFrame(CapturedFrame(surface: surface, size: size))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop(error)
    }
}
