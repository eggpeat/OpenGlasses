import Foundation
import Combine
import UIKit
import AVFoundation
import CoreMedia
import CoreVideo
import VideoToolbox
import HaishinKit
import RTMPHaishinKit

/// RTMP live broadcast service using HaishinKit v2.
///
/// Subscribes to the CameraService framePublisher and encodes UIImage frames
/// as H.264 video over RTMP to YouTube, Twitch, Kick, or any custom endpoint.
///
/// Architecture:
///   UIImage → CVPixelBuffer → CMSampleBuffer → MediaMixer → RTMPStream → RTMP server
///
/// Key patterns from SpecBridge analysis:
///   - Encoder priming: feed a CMSampleBuffer before calling publish() to avoid 0x0 metadata
///   - CPU-based pixel buffer conversion (no Metal/GPU) for background safety
@MainActor
class BroadcastService: ObservableObject {
    @Published var isBroadcasting = false
    @Published var broadcastError: String?
    @Published var broadcastDuration: TimeInterval = 0

    private var frameSubscription: AnyCancellable?
    private var durationTimer: Timer?
    private var startTime: Date?

    private let outputWidth = 720
    private let outputHeight = 1280 // Portrait for glasses
    nonisolated(unsafe) private var frameCount: Int = 0
    private let targetFPS: Double = 15

    /// Reused pixel-buffer pool so each frame doesn't allocate a fresh ~3.7 MB buffer (~55 MB/s of
    /// churn at 15 fps). Mirrors VideoRecordingService. Frames are pushed serially, matching its
    /// `nonisolated(unsafe)` discipline.
    nonisolated(unsafe) private var pixelBufferPool: CVPixelBufferPool?

    // HaishinKit components
    private var rtmpConnection: RTMPConnection?
    private var rtmpStream: RTMPStream?
    private var mediaMixer: MediaMixer?

    /// Start broadcasting to the configured RTMP endpoint.
    func startBroadcast(
        rtmpURL: String,
        streamKey: String,
        from publisher: PassthroughSubject<UIImage, Never>
    ) async throws {
        guard !isBroadcasting else { return }
        guard !rtmpURL.isEmpty, !streamKey.isEmpty else {
            broadcastError = "Configure RTMP URL and stream key in Settings"
            throw BroadcastError.notConfigured
        }

        // Parse URL: split into connection URL and stream name
        // e.g. rtmp://a.rtmp.youtube.com/live2 + streamKey
        let connectionURL: String
        let streamName: String

        if rtmpURL.hasSuffix("/") {
            connectionURL = String(rtmpURL.dropLast())
            streamName = streamKey
        } else {
            connectionURL = rtmpURL
            streamName = streamKey
        }

        NSLog("[Broadcast] Connecting to %@/%@", connectionURL, String(streamName.prefix(8)) + "...")

        do {
            // Create RTMP connection and stream
            let connection = RTMPConnection()
            let stream = RTMPStream(connection: connection)

            // Configure video encoding
            try await stream.setVideoSettings(VideoCodecSettings(
                videoSize: CGSize(width: outputWidth, height: outputHeight),
                bitRate: 1_500_000,
                profileLevel: kVTProfileLevel_H264_Main_AutoLevel as String,
                maxKeyFrameIntervalDuration: 2
            ))

            // Create MediaMixer and wire it to the stream
            let mixer = MediaMixer()
            await mixer.addOutput(stream)
            await mixer.setVideoMixerSettings(VideoMixerSettings(
                mode: .offscreen,
                isMuted: false
            ))

            self.rtmpConnection = connection
            self.rtmpStream = stream
            self.mediaMixer = mixer

            // Connect to RTMP server
            _ = try await connection.connect(connectionURL)
            NSLog("[Broadcast] Connected to RTMP server")

            // Encoder priming: send one blank frame before publish
            // This prevents the 0x0 metadata race condition found in SpecBridge
            if let primingBuffer = Self.createBlankSampleBuffer(width: outputWidth, height: outputHeight) {
                await mixer.append(primingBuffer)
                NSLog("[Broadcast] Encoder primed with blank frame")
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms for encoder to process
            }

            // Start publishing
            _ = try await stream.publish(streamName)
            NSLog("[Broadcast] Live! Publishing as '%@'", streamName.prefix(8).description)

        } catch {
            NSLog("[Broadcast] Connection failed: %@", error.localizedDescription)
            broadcastError = error.localizedDescription
            cleanup()
            throw BroadcastError.connectionFailed(error.localizedDescription)
        }

        isBroadcasting = true
        broadcastError = nil
        frameCount = 0
        startTime = Date()

        // Start duration timer
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if let start = self?.startTime {
                    self?.broadcastDuration = Date().timeIntervalSince(start)
                }
            }
        }

        // Subscribe to camera frames
        let interval = 1.0 / targetFPS
        frameSubscription = publisher
            .throttle(for: .seconds(interval), scheduler: DispatchQueue.global(qos: .userInitiated), latest: true)
            .sink { [weak self] image in
                self?.pushFrame(image)
            }
    }

    /// Stop the broadcast.
    func stopBroadcast() {
        guard isBroadcasting else { return }

        frameSubscription?.cancel()
        frameSubscription = nil
        durationTimer?.invalidate()
        durationTimer = nil
        pixelBufferPool = nil

        Task {
            if let stream = rtmpStream {
                _ = try? await stream.close()
            }
            if let connection = rtmpConnection {
                try? await connection.close()
            }
            cleanup()
        }

        isBroadcasting = false
        broadcastDuration = 0
        startTime = nil
        NSLog("[Broadcast] Stopped after %d frames", frameCount)
    }

    /// Formatted broadcast duration string (MM:SS)
    var formattedDuration: String {
        let minutes = Int(broadcastDuration) / 60
        let seconds = Int(broadcastDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Frame Encoding

    /// Dequeue a pixel buffer from the reused pool, lazily creating the pool on first use.
    private nonisolated func dequeuePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pixelBufferPool == nil {
            let poolAttrs: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3]
            let bufferAttrs: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary,
                                    bufferAttrs as CFDictionary, &pool)
            pixelBufferPool = pool
        }
        guard let pool = pixelBufferPool else { return nil }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess else {
            return nil
        }
        return buffer
    }

    private nonisolated func pushFrame(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return }

        let width = 720
        let height = 1280

        // Acquire a pixel buffer from the reused pool instead of allocating a new one per frame.
        guard let buffer = dequeuePixelBuffer(width: width, height: height) else { return }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        // Draw the image scaled to fill the buffer
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Create CMSampleBuffer
        guard let sampleBuffer = Self.createSampleBuffer(from: buffer) else { return }

        frameCount += 1

        // Feed to MediaMixer → RTMPStream
        Task { @MainActor [weak self] in
            guard let mixer = self?.mediaMixer else { return }
            await mixer.append(sampleBuffer)
        }
    }

    // MARK: - Helpers

    private static nonisolated func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )

        guard let desc = formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 15),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: desc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }

    private static func createBlankSampleBuffer(width: Int, height: Int) -> CMSampleBuffer? {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard let buffer = pixelBuffer else { return nil }

        // Fill with black
        CVPixelBufferLockBaseAddress(buffer, [])
        if let baseAddr = CVPixelBufferGetBaseAddress(buffer) {
            memset(baseAddr, 0, CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        return createSampleBuffer(from: buffer)
    }

    private func cleanup() {
        rtmpStream = nil
        rtmpConnection = nil
        mediaMixer = nil
    }
}

enum BroadcastError: LocalizedError {
    case notConfigured
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Broadcast not configured — set RTMP URL and stream key in Settings"
        case .connectionFailed(let reason): return "Broadcast connection failed: \(reason)"
        }
    }
}
