import AVFoundation
import Foundation

/// Native ITU-R BS.1770 integrated loudness + clipping detection.
/// Ported (and trimmed to LUFS + clip) from WaxOnWaxOff's AudioAnalyzer so
/// JustIn reports loudness with no external dependency.
enum LoudnessAnalyzer {
    struct Result: Sendable {
        let integratedLUFS: Double?
        let isClipping: Bool
    }

    static func analyze(
        url: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = perform(url: url, onProgress: onProgress)
                onProgress(1.0)
                continuation.resume(returning: result)
            }
        }
    }

    private static func perform(
        url: URL,
        onProgress: @Sendable (Double) -> Void
    ) -> Result {
        // autoreleasepool returns the file descriptor promptly when many files
        // are analyzed back to back.
        autoreleasepool {
            guard let file = try? AVAudioFile(forReading: url) else {
                return Result(integratedLUFS: nil, isClipping: false)
            }

            let format = file.processingFormat
            let frameCount = Int64(file.length)
            guard frameCount > 0 else { return Result(integratedLUFS: nil, isClipping: false) }

            let channels = Int(format.channelCount)
            let sr = format.sampleRate
            guard channels > 0, sr > 0 else { return Result(integratedLUFS: nil, isClipping: false) }

            let chunkSize: AVAudioFrameCount = 32_768
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
                return Result(integratedLUFS: nil, isClipping: false)
            }

            let kw = KWeightCoeffs(sampleRate: sr)
            var preW1 = [Double](repeating: 0, count: channels)
            var preW2 = [Double](repeating: 0, count: channels)
            var hpW1 = [Double](repeating: 0, count: channels)
            var hpW2 = [Double](repeating: 0, count: channels)

            // LUFS: 400 ms blocks at 75% overlap (one block every 100 ms),
            // implemented as a 4-deep ring of 100 ms hop sums.
            let hopFrames = max(1, Int((sr * 0.1).rounded()))
            let hopsPerBlock = 4
            var hopChannelSumSq = [Double](repeating: 0, count: channels)
            var hopFramesElapsed = 0
            var hopHistorySS: [[Double]] = Array(repeating: [], count: channels)
            var hopHistoryFrames: [Int] = []
            var blockMeanSqs = [Double]()

            var clipping = false
            file.framePosition = 0
            var lastReportedProgress = 0.0

            while file.framePosition < frameCount {
                do {
                    try file.read(into: buffer)
                } catch {
                    break
                }
                if buffer.frameLength == 0 { break }
                guard let channelData = buffer.floatChannelData else { break }

                let progress = Double(file.framePosition) / Double(frameCount)
                if progress - lastReportedProgress >= 0.02 {
                    lastReportedProgress = progress
                    onProgress(progress)
                }

                let frames = Int(buffer.frameLength)
                for frame in 0..<frames {
                    for ch in 0..<channels {
                        let x = Double(channelData[ch][frame])
                        if abs(x) >= 1.0 { clipping = true }

                        let y1 = kw.pre_b0 * x + preW1[ch]
                        preW1[ch] = kw.pre_b1 * x - kw.pre_a1 * y1 + preW2[ch]
                        preW2[ch] = kw.pre_b2 * x - kw.pre_a2 * y1

                        let y2 = kw.hp_b0 * y1 + hpW1[ch]
                        hpW1[ch] = kw.hp_b1 * y1 - kw.hp_a1 * y2 + hpW2[ch]
                        hpW2[ch] = kw.hp_b2 * y1 - kw.hp_a2 * y2

                        hopChannelSumSq[ch] += y2 * y2
                    }

                    hopFramesElapsed += 1
                    if hopFramesElapsed >= hopFrames {
                        for ch in 0..<channels {
                            hopHistorySS[ch].append(hopChannelSumSq[ch])
                            if hopHistorySS[ch].count > hopsPerBlock { hopHistorySS[ch].removeFirst() }
                            hopChannelSumSq[ch] = 0
                        }
                        hopHistoryFrames.append(hopFramesElapsed)
                        if hopHistoryFrames.count > hopsPerBlock { hopHistoryFrames.removeFirst() }
                        hopFramesElapsed = 0

                        if hopHistoryFrames.count == hopsPerBlock {
                            let totalHopFrames = hopHistoryFrames.reduce(0, +)
                            // BS.1770-4: block loudness uses the SUM over
                            // channels of G_c · mean-square_c. G_c = 1.0 for
                            // mono and stereo. (Averaging instead of summing
                            // makes stereo read 10·log10(2) ≈ 3 dB too low.)
                            var blockSumSq = 0.0
                            for ch in 0..<channels {
                                blockSumSq += hopHistorySS[ch].reduce(0, +) / Double(totalHopFrames)
                            }
                            blockMeanSqs.append(blockSumSq)
                        }
                    }
                }
            }

            // Flush a partial trailing block so very short clips still measure.
            if blockMeanSqs.isEmpty {
                let trailingFrames = hopHistoryFrames.reduce(0, +) + hopFramesElapsed
                if trailingFrames > 0 {
                    var blockSumSq = 0.0
                    for ch in 0..<channels {
                        blockSumSq += (hopHistorySS[ch].reduce(0, +) + hopChannelSumSq[ch]) / Double(trailingFrames)
                    }
                    blockMeanSqs.append(blockSumSq)
                }
            }

            let lufs = computeGatedLUFS(blockMeanSqs: blockMeanSqs)
            return Result(integratedLUFS: lufs, isClipping: clipping)
        }
    }

    /// ITU-R BS.1770 absolute + relative gating. Returns nil for silence/no data.
    private static func computeGatedLUFS(blockMeanSqs: [Double]) -> Double? {
        guard !blockMeanSqs.isEmpty else { return nil }

        let absThreshold = pow(10.0, (-70.0 + 0.691) / 10.0)
        let absoluteGated = blockMeanSqs.filter { $0 > absThreshold }
        guard !absoluteGated.isEmpty else { return nil }

        let ungatedMean = absoluteGated.reduce(0, +) / Double(absoluteGated.count)
        let ungatedLUFS = -0.691 + 10 * log10(max(ungatedMean, 1e-10))

        let relThreshold = pow(10.0, (ungatedLUFS - 10.0 + 0.691) / 10.0)
        let relativeGated = absoluteGated.filter { $0 > relThreshold }
        guard !relativeGated.isEmpty else { return ungatedLUFS }

        let gatedMean = relativeGated.reduce(0, +) / Double(relativeGated.count)
        return -0.691 + 10 * log10(max(gatedMean, 1e-10))
    }
}

/// ITU-R BS.1770 K-weighting biquad coefficients (pyloudnorm reference).
private struct KWeightCoeffs {
    let pre_b0, pre_b1, pre_b2, pre_a1, pre_a2: Double
    let hp_b0, hp_b1, hp_b2, hp_a1, hp_a2: Double

    init(sampleRate: Double) {
        let sqrt2 = 2.0.squareRoot()

        let db = 3.999843853973347
        let f0 = 1681.974450955533
        let Ks = tan(Double.pi * f0 / sampleRate)
        let Kssq = Ks * Ks
        let Vh = pow(10.0, db / 20.0)
        let Vb = pow(Vh, 0.4996667741545416)
        let d1 = 1 + sqrt2 * Ks + Kssq
        pre_b0 = (Vh + Vb * sqrt2 * Ks + Kssq) / d1
        pre_b1 = 2 * (Kssq - Vh) / d1
        pre_b2 = (Vh - Vb * sqrt2 * Ks + Kssq) / d1
        pre_a1 = 2 * (Kssq - 1) / d1
        pre_a2 = (1 - sqrt2 * Ks + Kssq) / d1

        let f0h = 38.13547087602444
        let Q = 0.5003270373253953
        let Kh = tan(Double.pi * f0h / sampleRate)
        let Khsq = Kh * Kh
        let d2 = 1 + Kh / Q + Khsq
        hp_b0 = 1.0 / d2
        hp_b1 = -2.0 / d2
        hp_b2 = 1.0 / d2
        hp_a1 = 2 * (Khsq - 1) / d2
        hp_a2 = (1 - Kh / Q + Khsq) / d2
    }
}
