import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

protocol VideoEncoderDelegate: AnyObject {
    func videoEncoder(_ encoder: VideoEncoder, didEncodeFrame data: Data, timestamp: CMTime, isKeyFrame: Bool)
    func videoEncoder(_ encoder: VideoEncoder, didEncounterError error: Error)
}

class VideoEncoder {
    weak var delegate: VideoEncoderDelegate?

    private var session: VTCompressionSession?
    private var frameCount: Int64 = 0
    private let gopSize: Int = 60

    var bitrate: Int = 2_000_000 {
        didSet {
            updateBitrate()
        }
    }

    var width: Int32 = 1920
    var height: Int32 = 1080

    init(width: Int32 = 1920, height: Int32 = 1080) {
        self.width = width
        self.height = height
    }

    func setup() throws {
        var session: VTCompressionSession?

        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true] as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: encoderCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            throw VideoEncoderError.sessionCreationFailed(status)
        }

        self.session = session

        try setProperty(kVTCompressionPropertyKey_RealTime, true as CFBoolean)
        try setProperty(kVTCompressionPropertyKey_AverageBitRate, bitrate as CFNumber)
        try setProperty(kVTCompressionPropertyKey_MaxKeyFrameInterval, gopSize as CFNumber)
        try setProperty(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main_AutoLevel)

        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    private func setProperty(_ key: CFString, _ value: CFTypeRef) throws {
        guard let session = session else { throw VideoEncoderError.sessionNotInitialized }
        let status = VTSessionSetProperty(session, key: key, value: value)
        guard status == noErr else {
            throw VideoEncoderError.propertySetFailed(key as String, status)
        }
    }

    func encode(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let session = session else { return }

        let frameProperties = [
            kVTEncodeFrameOptionKey_ForceKeyFrame: frameCount % Int64(gopSize) == 0
        ] as CFDictionary

        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: timestamp,
            duration: .invalid,
            frameProperties: frameProperties,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )

        if status != noErr {
            delegate?.videoEncoder(self, didEncounterError: VideoEncoderError.encodingFailed(status))
        }

        frameCount += 1
    }

    func forceKeyFrame() {
        frameCount = 0
    }

    private func updateBitrate() {
        guard let session = session else { return }
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_AverageBitRate,
            value: bitrate as CFNumber
        )
    }

    func invalidate() {
        guard let session = session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        self.session = nil
    }

    deinit {
        invalidate()
    }
}

private func encoderCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard status == noErr else { return }
    guard let sampleBuffer = sampleBuffer else { return }
    guard let outputCallbackRefCon = outputCallbackRefCon else { return }

    let encoder = Unmanaged<VideoEncoder>.fromOpaque(outputCallbackRefCon).takeUnretainedValue()

    let isKeyFrame = sampleBuffer.sampleAttachments.first?[
        kCMSampleAttachmentKey_NotSync as String
    ] as? Bool != true

    if let dataBuffer = sampleBuffer.dataBuffer {
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        if let dataPointer = dataPointer, totalLength > 0 {
            let data = Data(bytes: dataPointer, count: totalLength)
            encoder.delegate?.videoEncoder(encoder, didEncodeFrame: data, timestamp: sampleBuffer.presentationTimeStamp, isKeyFrame: isKeyFrame)
        }
    }
}

enum VideoEncoderError: LocalizedError {
    case sessionCreationFailed(OSStatus)
    case sessionNotInitialized
    case propertySetFailed(String, OSStatus)
    case encodingFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed(let status):
            return "Failed to create compression session: \(status)"
        case .sessionNotInitialized:
            return "Compression session not initialized"
        case .propertySetFailed(let key, let status):
            return "Failed to set property \(key): \(status)"
        case .encodingFailed(let status):
            return "Frame encoding failed: \(status)"
        }
    }
}
