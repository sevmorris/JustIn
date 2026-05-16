import AVFoundation
import Foundation

/// Cooperative cancellation flag the background reader polls. A new selection
/// flips the previous token so its in-flight read stops promptly.
final class WaveformToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
}

/// Reads PCM via AVAssetReader and produces per-lane RMS buckets, emitting
/// partial results so the view fills left-to-right while reading.
enum WaveformGenerator {
    static func generate(
        url: URL,
        buckets: Int,
        token: WaveformToken,
        onPartial: @escaping @Sendable (WaveformData) -> Void
    ) async -> WaveformData? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }

        let durationSeconds = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        var sampleRate = 44_100.0
        var sourceChannels = 1
        if let formats = try? await track.load(.formatDescriptions),
           let format = formats.first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
            if asbd.mSampleRate > 0 { sampleRate = asbd.mSampleRate }
            sourceChannels = max(1, Int(asbd.mChannelsPerFrame))
        }
        let lanes = sourceChannels >= 2 ? 2 : 1
        let estimatedFrames = max(buckets, Int(durationSeconds * sampleRate))

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = render(
                    asset: asset,
                    track: track,
                    buckets: buckets,
                    lanes: lanes,
                    sourceChannels: sourceChannels,
                    estimatedFrames: estimatedFrames,
                    token: token,
                    onPartial: onPartial
                )
                continuation.resume(returning: result)
            }
        }
    }

    private static func render(
        asset: AVURLAsset,
        track: AVAssetTrack,
        buckets: Int,
        lanes: Int,
        sourceChannels: Int,
        estimatedFrames: Int,
        token: WaveformToken,
        onPartial: @Sendable (WaveformData) -> Void
    ) -> WaveformData? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        let samplesPerBucket = max(1, estimatedFrames / buckets)
        let emitStride = max(1, buckets / 120)
        var sumSquares = [[Double]](repeating: [Double](repeating: 0, count: buckets), count: lanes)
        var frameCounts = [Int](repeating: 0, count: buckets)
        var finalized = [[Float]](repeating: [Float](repeating: 0, count: buckets), count: lanes)
        var globalFrame = 0
        var lastEmittedBucket = -1

        func finalize(upTo bucket: Int) {
            guard bucket > lastEmittedBucket else { return }
            for b in (lastEmittedBucket + 1)...bucket where b < buckets {
                let n = frameCounts[b]
                guard n > 0 else { continue }
                for lane in 0..<lanes {
                    finalized[lane][b] = Float((sumSquares[lane][b] / Double(n)).squareRoot())
                }
            }
            lastEmittedBucket = bucket
        }

        while reader.status == .reading {
            if token.isCancelled {
                reader.cancelReading()
                return nil
            }
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            defer { CMSampleBufferInvalidate(sampleBuffer) }
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            var lengthAtOffset = 0
            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(
                block, atOffset: 0,
                lengthAtOffsetOut: &lengthAtOffset,
                totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
                let dataPointer else { continue }

            let floatCount = totalLength / MemoryLayout<Float>.size
            dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { samples in
                let frames = floatCount / sourceChannels
                for f in 0..<frames {
                    let bucket = (globalFrame + f) / samplesPerBucket
                    if bucket >= buckets { break }
                    for lane in 0..<lanes {
                        let s = Double(samples[f * sourceChannels + lane])
                        sumSquares[lane][bucket] += s * s
                    }
                    frameCounts[bucket] += 1
                }
                globalFrame += frames
            }

            let currentBucket = min(buckets - 1, globalFrame / samplesPerBucket) - 1
            if currentBucket - lastEmittedBucket >= emitStride {
                finalize(upTo: currentBucket)
                onPartial(WaveformData(lanes: finalized, bucketCount: buckets))
            }
        }

        if reader.status == .failed { return nil }
        if token.isCancelled { return nil }
        finalize(upTo: buckets - 1)
        return WaveformData(lanes: finalized, bucketCount: buckets)
    }
}
