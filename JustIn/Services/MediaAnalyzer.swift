import AVFoundation
import Foundation

enum AnalysisError: LocalizedError {
    case unreadable
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Could not read the file"
        case .unsupported:
            return "Unsupported format or unreadable file"
        }
    }
}

enum MediaAnalyzer {
    // MARK: - Phase 1: fast AVFoundation fields

    static func analyze(url: URL) async throws -> MediaInfo {
        let format = url.pathExtension.uppercased()
        let fileSize = fileSize(at: url)
        let modificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        let asset = AVURLAsset(url: url)

        let duration = try? await asset.load(.duration)
        let durationSeconds: TimeInterval? = duration.map(CMTimeGetSeconds).flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        }

        let audio = try await audioInfo(for: asset)
        let video = try await videoInfo(for: asset)

        let isPlayable = (try? await asset.load(.isPlayable)) ?? false
        if !isPlayable, durationSeconds == nil, audio.sampleRate == nil, video.codec == nil {
            throw AnalysisError.unsupported
        }

        var bitRate: Double?
        if let durationSeconds, durationSeconds > 0, fileSize > 0 {
            bitRate = (Double(fileSize) * 8.0) / durationSeconds
        }

        let metadataSummary = try? await metadataSummary(for: asset)
        let chapterCount = try? await chapterCount(for: asset)

        return MediaInfo(
            format: format.isEmpty ? "Media" : format,
            duration: durationSeconds,
            sampleRate: audio.sampleRate,
            channelCount: audio.channels,
            bitDepth: audio.bitDepth,
            audioCodec: audio.codec ?? (format.isEmpty ? nil : (video.codec == nil ? format : nil)),
            videoCodec: video.codec,
            frameRate: video.frameRate,
            bitRate: bitRate,
            fileSize: fileSize,
            modificationDate: modificationDate,
            audioBitRate: audio.dataRate,
            videoBitRate: video.dataRate,
            metadataSummary: metadataSummary,
            chapterCount: chapterCount,
            width: video.width,
            height: video.height,
            colorSpace: video.colorSpace,
            isHDR: video.isHDR
        )
    }

    // MARK: - Phase 2: slow fields (full audio read + subprocesses)

    static func extendedStats(
        url: URL,
        hasAudio: Bool,
        duration: TimeInterval?,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async -> ExtendedStats {
        let ffmpegContributes = hasAudio
            && FFmpegLocator.isAvailable
            && (duration ?? 0) > 0
        let combiner = ProgressCombiner(
            useNative: hasAudio,
            useFFmpeg: ffmpegContributes,
            emit: onProgress
        )

        async let native = LoudnessAnalyzer.analyze(url: url) { progress in
            combiner.reportNative(progress)
        }
        async let ffmpeg = FFmpegProbe.truePeakAndLRA(url: url, duration: duration) { progress in
            combiner.reportFFmpeg(progress)
        }
        async let vbr = FFmpegProbe.isVBR(url: url)

        let nativeResult = await native
        let (truePeak, lra) = await ffmpeg
        let isVBR = await vbr

        return ExtendedStats(
            integratedLUFS: nativeResult.integratedLUFS,
            truePeak: truePeak,
            loudnessRange: lra,
            isClipping: hasAudio ? nativeResult.isClipping : nil,
            isVBR: isVBR
        )
    }

    // MARK: - Helpers

    private static func fileSize(at url: URL) -> Int64 {
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return Int64(size ?? 0)
    }

    private static func audioInfo(
        for asset: AVURLAsset
    ) async throws -> (sampleRate: Double?, channels: Int?, bitDepth: Int?, codec: String?, dataRate: Double?) {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return (nil, nil, nil, nil, nil)
        }

        let estimatedRate = try? await track.load(.estimatedDataRate)
        let dataRate = (estimatedRate.map(Double.init)).flatMap { $0 > 0 ? $0 : nil }

        let formatDescriptions = try await track.load(.formatDescriptions)
        for formatDesc in formatDescriptions {
            guard CMFormatDescriptionGetMediaType(formatDesc) == kCMMediaType_Audio else { continue }

            var sampleRate: Double?
            var channels: Int?
            var bitDepth: Int?
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {
                sampleRate = asbd.mSampleRate
                channels = Int(asbd.mChannelsPerFrame)
                if asbd.mBitsPerChannel > 0 {
                    bitDepth = Int(asbd.mBitsPerChannel)
                }
            }
            let codec = CMFormatDescriptionGetMediaSubType(formatDesc).codecName
            return (sampleRate, channels, bitDepth, codec, dataRate)
        }

        return (nil, nil, nil, nil, dataRate)
    }

    private static func videoInfo(
        for asset: AVURLAsset
    ) async throws -> (codec: String?, frameRate: Double?, dataRate: Double?,
                       width: Int?, height: Int?, colorSpace: String?, isHDR: Bool) {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            return (nil, nil, nil, nil, nil, nil, false)
        }

        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let frameRate: Double? = nominalFrameRate > 0 ? Double(nominalFrameRate) : nil

        let estimatedRate = try? await track.load(.estimatedDataRate)
        let dataRate = (estimatedRate.map(Double.init)).flatMap { $0 > 0 ? $0 : nil }

        var width: Int?
        var height: Int?
        if let size = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform) {
            let resolved = size.applying(transform)
            width = Int(abs(resolved.width).rounded())
            height = Int(abs(resolved.height).rounded())
        }

        let formatDescriptions = try await track.load(.formatDescriptions)
        for formatDesc in formatDescriptions
        where CMFormatDescriptionGetMediaType(formatDesc) == kCMMediaType_Video {
            let codec = CMFormatDescriptionGetMediaSubType(formatDesc).codecName
            let (colorSpace, isHDR) = colorInfo(formatDesc)
            return (codec, frameRate, dataRate, width, height, colorSpace, isHDR)
        }

        return (nil, frameRate, dataRate, width, height, nil, false)
    }

    private static func colorInfo(_ desc: CMFormatDescription) -> (String?, Bool) {
        let primaries = CMFormatDescriptionGetExtension(
            desc, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String
        let transfer = CMFormatDescriptionGetExtension(
            desc, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String

        var space: String?
        if let primaries {
            if primaries == (kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String) {
                space = "Rec. 709"
            } else if primaries == (kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String) {
                space = "Rec. 2020"
            } else if primaries == (kCMFormatDescriptionColorPrimaries_P3_D65 as String) {
                space = "Display P3"
            } else if primaries == (kCMFormatDescriptionColorPrimaries_EBU_3213 as String) {
                space = "EBU 3213"
            } else if primaries == (kCMFormatDescriptionColorPrimaries_SMPTE_C as String) {
                space = "SMPTE-C"
            } else {
                space = primaries
            }
        }

        let isPQ = transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
        let isHLG = transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
        let isHDR = isPQ || isHLG
        if isHDR {
            let tag = isPQ ? "HDR PQ" : "HDR HLG"
            space = space.map { "\($0) · \(tag)" } ?? tag
        }
        return (space, isHDR)
    }

    private static func metadataSummary(for asset: AVURLAsset) async throws -> String {
        let common = try await asset.load(.commonMetadata)
        var present: [String] = []
        if common.contains(where: { $0.commonKey == .commonKeyTitle }) { present.append("Title") }
        if common.contains(where: { $0.commonKey == .commonKeyArtist }) { present.append("Artist") }
        if common.contains(where: { $0.commonKey == .commonKeyAlbumName }) { present.append("Album") }
        if common.contains(where: { $0.commonKey == .commonKeyArtwork }) { present.append("Artwork") }

        if let id3 = try? await asset.loadMetadata(for: .id3Metadata),
           id3.contains(where: { $0.identifier == .id3MetadataTrackNumber }) {
            present.append("Track#")
        } else if let itunes = try? await asset.loadMetadata(for: .iTunesMetadata),
                  itunes.contains(where: { $0.identifier == .iTunesMetadataTrackNumber }) {
            present.append("Track#")
        }

        return present.isEmpty ? "None" : present.joined(separator: ", ")
    }

    private static func chapterCount(for asset: AVURLAsset) async throws -> Int {
        let groups = try await asset.loadChapterMetadataGroups(
            bestMatchingPreferredLanguages: Locale.preferredLanguages)
        return groups.count
    }
}

/// Merges the two concurrent loudness sub-passes into one 0...1 value so all
/// four loudness cards advance in lockstep. Lock-guarded; safe to call from
/// the analyzer background queues.
final class ProgressCombiner: @unchecked Sendable {
    private let lock = NSLock()
    private var nativeProgress = 0.0
    private var ffmpegProgress = 0.0
    private let useNative: Bool
    private let useFFmpeg: Bool
    private let emit: @Sendable (Double) -> Void

    init(useNative: Bool, useFFmpeg: Bool, emit: @escaping @Sendable (Double) -> Void) {
        self.useNative = useNative
        self.useFFmpeg = useFFmpeg
        self.emit = emit
    }

    func reportNative(_ value: Double) {
        update { self.nativeProgress = value }
    }

    func reportFFmpeg(_ value: Double) {
        update { self.ffmpegProgress = value }
    }

    private func update(_ mutate: () -> Void) {
        lock.lock()
        mutate()
        var total = 0.0
        var count = 0
        if useNative { total += nativeProgress; count += 1 }
        if useFFmpeg { total += ffmpegProgress; count += 1 }
        let combined = count > 0 ? total / Double(count) : 1.0
        lock.unlock()
        emit(min(1, max(0, combined)))
    }
}

extension FourCharCode {
    var codecName: String {
        switch self {
        case kAudioFormatLinearPCM: return "Linear PCM"
        case kAudioFormatAppleLossless: return "Apple Lossless"
        case kAudioFormatMPEG4AAC: return "AAC"
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatAC3: return "AC-3"
        case kAudioFormatEnhancedAC3: return "E-AC-3"
        case kAudioFormatFLAC: return "FLAC"
        case kAudioFormatOpus: return "Opus"
        case kCMVideoCodecType_H264: return "H.264"
        case kCMVideoCodecType_HEVC: return "HEVC (H.265)"
        case kCMVideoCodecType_MPEG4Video: return "MPEG-4"
        case kCMVideoCodecType_AppleProRes422: return "ProRes 422"
        case kCMVideoCodecType_AppleProRes4444: return "ProRes 4444"
        case kCMVideoCodecType_AppleProResRAW: return "ProRes RAW"
        default:
            var code = self.bigEndian
            let bytes = withUnsafeBytes(of: &code) { Array($0) }
            if let str = String(bytes: bytes, encoding: .ascii),
               str.allSatisfy({ $0.isASCII && !$0.isWhitespace }) {
                return str
            }
            return "Unknown (\(self))"
        }
    }
}
