import Foundation
import ScreenCaptureKit
import CoreVideo
import CoreMedia

protocol ScreenCaptureDelegate: AnyObject {
    func screenCapture(_ capture: ScreenCapture, didOutputFrame frame: CVPixelBuffer, timestamp: CMTime)
    func screenCapture(_ capture: ScreenCapture, didEncounterError error: Error)
}

class ScreenCapture: NSObject {
    weak var delegate: ScreenCaptureDelegate?

    private var stream: SCStream?
    private var isCapturing = false
    private var configuration: SCStreamConfiguration
    private var filter: SCContentFilter?

    var frameRate: Int = 30 {
        didSet {
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        }
    }

    override init() {
        configuration = SCStreamConfiguration()
        super.init()
        setupDefaultConfiguration()
    }

    private func setupDefaultConfiguration() {
        configuration.width = 1920
        configuration.height = 1080
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }

    func getAvailableDisplays() async throws -> [SCDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        return content.displays
    }

    func getAvailableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        return content.windows.filter { $0.isOnScreen && $0.frame.width > 100 }
    }

    func startCapture(display: SCDisplay) async throws {
        guard !isCapturing else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        filter = SCContentFilter(display: display, excludingWindows: [])

        stream = SCStream(filter: filter!, configuration: configuration, delegate: self)
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        try await stream?.startCapture()

        isCapturing = true
    }

    func startCapture(window: SCWindow) async throws {
        guard !isCapturing else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        filter = SCContentFilter(desktopIndependentWindow: window)

        stream = SCStream(filter: filter!, configuration: configuration, delegate: self)
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        try await stream?.startCapture()

        isCapturing = true
    }

    func stopCapture() async {
        guard isCapturing else { return }
        try? await stream?.stopCapture()
        stream = nil
        filter = nil
        isCapturing = false
    }

    func updateResolution(width: Int, height: Int) {
        configuration.width = width
        configuration.height = height
    }
}

extension ScreenCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isCapturing = false
        delegate?.screenCapture(self, didEncounterError: error)
    }
}

extension ScreenCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let imageBuffer = sampleBuffer.imageBuffer else { return }

        delegate?.screenCapture(self, didOutputFrame: imageBuffer, timestamp: sampleBuffer.presentationTimeStamp)
    }
}
