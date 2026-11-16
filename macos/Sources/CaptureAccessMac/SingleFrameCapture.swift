import CaptureCore
import CoreImage
import CoreMedia
import ScreenCaptureKit

/// Uses the existing picker filter and stops as soon as one complete frame is
/// available. Never expands capture to a display or requests audio output.
enum SingleFrameCapture {
    static func capture(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        let output = FrameOutput()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        let queue = DispatchQueue(label: "local.captureaccess.single-frame")
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)

        do {
            try Task.checkCancellation()
            try await stream.startCapture()
            try Task.checkCancellation()
            let deadline = Task {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) }
                catch { return }
                output.finishWithoutFrame()
            }
            defer { deadline.cancel() }
            // AsyncThrowingStream ends on task cancellation, so cancellation and
            // the model's timeout both reach stopCapture below.
            for try await image in output.frames {
                try Task.checkCancellation()
                try await stream.stopCapture()
                return image
            }
            throw CancellationError()
        } catch {
            try? await stream.stopCapture()
            throw error
        }
    }
}

private final class FrameOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    let frames: AsyncThrowingStream<CGImage, Error>
    private let continuation: AsyncThrowingStream<CGImage, Error>.Continuation
    private let context = CIContext(options: [.cacheIntermediates: false])
    // Video callbacks use one serial queue. Avoid converting queued frames once
    // the requested frame has already been delivered.
    private var deliveredFrame = false

    override init() {
        let pair = AsyncThrowingStream<CGImage, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        frames = pair.stream
        continuation = pair.continuation
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard !deliveredFrame, outputType == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let buffer = sampleBuffer.imageBuffer else { return }
        let source = CIImage(cvPixelBuffer: buffer)
        guard let image = context.createCGImage(source, from: source.extent) else {
            deliveredFrame = true
            continuation.finish(throwing: CaptureFailure.imageValidation)
            return
        }
        do {
            guard try !CaptureImageValidation.isFullyTransparent(image) else {
                // The compositor can produce an empty initial complete frame.
                // Wait for a visible frame until the bounded deadline instead.
                return
            }
            deliveredFrame = true
            continuation.yield(image)
            continuation.finish()
        } catch {
            deliveredFrame = true
            continuation.finish(throwing: error)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        continuation.finish(throwing: error)
    }

    func finishWithoutFrame() {
        continuation.finish(throwing: CaptureFailure.emptyImage)
    }
}
