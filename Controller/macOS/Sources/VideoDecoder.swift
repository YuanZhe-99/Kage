import Foundation
import VideoToolbox
import CoreVideo
import CoreMedia

protocol VideoDecoderDelegate: AnyObject {
    func videoDecoder(_ decoder: VideoDecoder, didDecodeFrame pixelBuffer: CVPixelBuffer, timestamp: CMTime)
    func videoDecoder(_ decoder: VideoDecoder, didEncounterError error: Error)
}

class VideoDecoder {
    weak var delegate: VideoDecoderDelegate?

    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?

    init() {}

    func setup() throws {
        let decoderSpecification = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true
        ] as CFDictionary

        var session: VTDecompressionSession?

        guard let formatDescription = formatDescription else {
            throw VideoDecoderError.noFormatDescription
        }

        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { decompressionOutputRefCon, sourceFrameRefCon, status, infoFlags, imageBuffer, presentationTimeStamp, presentationDuration in
                guard status == noErr else { return }
                guard let imageBuffer = imageBuffer else { return }
                guard let decompressionOutputRefCon = decompressionOutputRefCon else { return }

                let decoder = Unmanaged<VideoDecoder>.fromOpaque(decompressionOutputRefCon).takeUnretainedValue()
                decoder.delegate?.videoDecoder(decoder, didDecodeFrame: imageBuffer, timestamp: presentationTimeStamp)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        let status = VTDecompressionSessionCreate(
            allocator: nil,
            formatDescription: formatDescription,
            decoderSpecification: decoderSpecification,
            imageBufferAttributes: nil,
            outputCallback: &callbackRecord,
            decompressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            throw VideoDecoderError.sessionCreationFailed(status)
        }

        self.session = session
    }

    func updateFormatDescription(_ formatDescription: CMVideoFormatDescription) {
        self.formatDescription = formatDescription
    }

    func decode(data: Data, timestamp: CMTime) {
        guard let session = session else { return }

        let blockBuffer = try? createBlockBuffer(from: data)
        guard let blockBuffer = blockBuffer else { return }

        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: timestamp,
            decodeTimeStamp: timestamp
        )

        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let sampleBuffer = sampleBuffer else { return }

        let decodeFlags = VTDecodeFrameFlags._EnableAsynchronousDecompression
        var outputFlags = VTDecodeInfoFlags()

        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: decodeFlags,
            frameRefcon: nil,
            infoFlagsOut: &outputFlags
        )
    }

    private func createBlockBuffer(from data: Data) throws -> CMBlockBuffer {
        var blockBuffer: CMBlockBuffer?

        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr, let blockBuffer = blockBuffer else {
            throw VideoDecoderError.blockBufferCreationFailed(status)
        }

        let copyStatus = CMBlockBufferReplaceDataBytes(
            with: (data as NSData).bytes,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: data.count
        )

        guard copyStatus == noErr else {
            throw VideoDecoderError.blockBufferCopyFailed(copyStatus)
        }

        return blockBuffer
    }

    func invalidate() {
        guard let session = session else { return }
        VTDecompressionSessionInvalidate(session)
        self.session = nil
    }

    deinit {
        invalidate()
    }
}

enum VideoDecoderError: LocalizedError {
    case noFormatDescription
    case sessionCreationFailed(OSStatus)
    case blockBufferCreationFailed(OSStatus)
    case blockBufferCopyFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noFormatDescription:
            return "No format description available"
        case .sessionCreationFailed(let status):
            return "Failed to create decompression session: \(status)"
        case .blockBufferCreationFailed(let status):
            return "Failed to create block buffer: \(status)"
        case .blockBufferCopyFailed(let status):
            return "Failed to copy data to block buffer: \(status)"
        }
    }
}
