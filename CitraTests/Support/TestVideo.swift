import AVFoundation
import CoreMedia
import Foundation

/// Writes a short real H.264 video (64×64, 10 fps), optionally with an AAC audio track (440 Hz tone).
enum TestVideo {
    struct Failure: Error { let reason: String }

    static func make(_ url: URL, seconds: Int = 1, audio: Bool = true, fileType: AVFileType = .mp4) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
        ])
        writer.add(video)
        var sound: AVAssetWriterInput?
        if audio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
            ])
            writer.add(input)
            sound = input
        }
        guard writer.startWriting() else { throw Failure(reason: "\(writer.error?.localizedDescription ?? "start")") }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<(seconds * 10) {
            while !video.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { throw Failure(reason: "no pixel buffer pool") }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw Failure(reason: "no pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(frame * 20 % 255), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        video.markAsFinished()

        if let sound {
            let rate = 44_100, chunk = 4_410
            var format = AudioStreamBasicDescription(mSampleRate: Double(rate), mFormatID: kAudioFormatLinearPCM,
                                                     mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                                                     mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
                                                     mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
            var description: CMAudioFormatDescription?
            CMAudioFormatDescriptionCreate(allocator: nil, asbd: &format, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                           magicCookie: nil, extensions: nil, formatDescriptionOut: &description)
            for start in stride(from: 0, to: rate * seconds, by: chunk) {
                while !sound.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
                let samples = (0..<chunk).map { Int16(8000 * sin(2 * Double.pi * 440 * Double(start + $0) / Double(rate))) }
                var block: CMBlockBuffer?
                CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: chunk * 2, blockAllocator: nil,
                                                   customBlockSource: nil, offsetToData: 0, dataLength: chunk * 2, flags: 0, blockBufferOut: &block)
                guard let block else { throw Failure(reason: "no block buffer") }
                samples.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: chunk * 2) }
                var sample: CMSampleBuffer?
                CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: description!,
                                                                     sampleCount: chunk, presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(rate)),
                                                                     packetDescriptions: nil, sampleBufferOut: &sample)
                guard let sample else { throw Failure(reason: "no sample buffer") }
                sound.append(sample)
            }
            sound.markAsFinished()
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw Failure(reason: writer.error?.localizedDescription ?? "finish") }
    }

    static func tracks(_ url: URL, _ type: AVMediaType) async throws -> Int {
        try await AVURLAsset(url: url).loadTracks(withMediaType: type).count
    }
}
