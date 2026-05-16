import Foundation

/// Subprocess-backed measurements: true peak + loudness range via ffmpeg's
/// ebur128 filter, and CBR/VBR detection via ffprobe packet sizes. Every entry
/// point degrades to `nil` when the binary is missing or output is unparseable.
enum FFmpegProbe {
    /// One ebur128 pass. Integrated LUFS is computed natively elsewhere, so
    /// only true peak (dBTP) and LRA are taken from here. `onProgress` is
    /// driven by ffmpeg's `time=` stderr token, compared against `duration`.
    static func truePeakAndLRA(
        url: URL,
        duration: TimeInterval?,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async -> (truePeak: Double?, lra: Double?) {
        guard let ffmpeg = FFmpegLocator.ffmpegPath else { return (nil, nil) }
        // No -nostats: we need ffmpeg's periodic `time=` progress on stderr.
        let args = [
            "-hide_banner",
            "-i", url.path,
            "-af", "ebur128=peak=true",
            "-f", "null", "-",
        ]
        let stderr = await runStreamingStderr(ffmpeg, args, duration: duration, onProgress: onProgress)
        onProgress(1.0)
        guard let stderr else { return (nil, nil) }

        // The ebur128 summary is printed to stderr. Per-frame lines also carry
        // I:/LRA:, so parse only the trailing "Summary:" block.
        guard let summaryRange = stderr.range(of: "Summary:", options: .backwards) else {
            return (nil, nil)
        }
        let summary = String(stderr[summaryRange.lowerBound...])

        let lra = firstDouble(in: summary, pattern: #"LRA:\s*(-?\d+(?:\.\d+)?)\s*LU"#)
        var truePeak: Double?
        if let tpRange = summary.range(of: "True peak:") {
            let tail = String(summary[tpRange.lowerBound...])
            truePeak = firstDouble(in: tail, pattern: #"Peak:\s*(-?\d+(?:\.\d+)?)\s*dBFS"#)
        }
        return (truePeak, lra)
    }

    /// Returns true for VBR, false for CBR, nil when undeterminable. Inspects
    /// packet-size variance over the first 30 s of the primary audio stream.
    static func isVBR(url: URL) async -> Bool? {
        guard let ffprobe = FFmpegLocator.ffprobePath else { return nil }
        let args = [
            "-v", "error",
            "-select_streams", "a:0",
            "-read_intervals", "%30",
            "-show_entries", "packet=size",
            "-of", "csv=p=0",
            url.path,
        ]
        guard let result = await run(ffprobe, args) else { return nil }
        let sizes = result.stdout
            .split(separator: "\n")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard sizes.count >= 20 else { return nil }

        let mean = sizes.reduce(0, +) / Double(sizes.count)
        guard mean > 0 else { return nil }
        let variance = sizes.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(sizes.count)
        let coefficientOfVariation = variance.squareRoot() / mean
        return coefficientOfVariation > 0.02
    }

    // MARK: - Helpers

    /// Thread-safe accumulator the readability handler can mutate from its
    /// private queue while we snapshot the tail for live `time=` parsing.
    private final class StreamBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock(); data.append(chunk); lock.unlock()
        }

        func tailString(_ maxBytes: Int) -> String {
            lock.lock(); let snapshot = data.suffix(maxBytes); lock.unlock()
            return String(decoding: snapshot, as: UTF8.self)
        }

        var fullString: String {
            lock.lock(); let snapshot = data; lock.unlock()
            return String(decoding: snapshot, as: UTF8.self)
        }
    }

    private static func runStreamingStderr(
        _ path: String,
        _ args: [String],
        duration: TimeInterval?,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                let buffer = StreamBuffer()
                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    guard !chunk.isEmpty else { return }
                    buffer.append(chunk)
                    if let duration, duration > 0,
                       let seconds = lastTimeSeconds(in: buffer.tailString(8192)) {
                        onProgress(min(1.0, seconds / duration))
                    }
                }
                // Drain stdout so a full pipe can't stall the process.
                outPipe.fileHandleForReading.readabilityHandler = { handle in
                    _ = handle.availableData
                }

                do {
                    try process.run()
                } catch {
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(returning: nil)
                    return
                }
                process.waitUntilExit()
                errPipe.fileHandleForReading.readabilityHandler = nil
                outPipe.fileHandleForReading.readabilityHandler = nil
                if let remaining = try? errPipe.fileHandleForReading.readToEnd() {
                    buffer.append(remaining)
                }
                continuation.resume(returning: buffer.fullString)
            }
        }
    }

    private static func lastTimeSeconds(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(
            pattern: #"time=(\d+):(\d+):(\d+(?:\.\d+)?)"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard let match = matches.last,
              let hRange = Range(match.range(at: 1), in: text),
              let mRange = Range(match.range(at: 2), in: text),
              let sRange = Range(match.range(at: 3), in: text),
              let hours = Double(text[hRange]),
              let minutes = Double(text[mRange]),
              let seconds = Double(text[sRange]) else {
            return nil
        }
        return hours * 3600 + minutes * 60 + seconds
    }

    private static func firstDouble(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[captureRange])
    }

    private static func run(_ path: String, _ args: [String]) async -> (stdout: String, stderr: String)? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                var outData = Data()
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                    group.leave()
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                process.waitUntilExit()
                group.wait()
                continuation.resume(returning: (
                    String(decoding: outData, as: UTF8.self),
                    String(decoding: errData, as: UTF8.self)
                ))
            }
        }
    }
}
