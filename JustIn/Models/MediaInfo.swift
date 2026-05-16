import Foundation

/// Phase 1 — fast fields, extracted from AVFoundation only.
struct MediaInfo: Sendable, Equatable {
    let format: String
    let duration: TimeInterval?
    let sampleRate: Double?
    let channelCount: Int?
    let bitDepth: Int?
    let audioCodec: String?
    let videoCodec: String?
    let frameRate: Double?
    let bitRate: Double?
    let fileSize: Int64
    let modificationDate: Date?
    let audioBitRate: Double?
    let videoBitRate: Double?
    let metadataSummary: String?
    let chapterCount: Int?
    // Video-only
    let width: Int?
    let height: Int?
    let colorSpace: String?
    let isHDR: Bool

    var hasVideo: Bool { videoCodec != nil }
    var hasAudio: Bool { audioCodec != nil || sampleRate != nil }
}

/// Phase 2 — slow fields requiring a full audio read and/or subprocesses.
struct ExtendedStats: Sendable, Equatable {
    /// Native ITU-R BS.1770 integrated loudness (no ffmpeg needed).
    let integratedLUFS: Double?
    /// True peak (dBTP) — ffmpeg ebur128 only; nil when ffmpeg absent.
    let truePeak: Double?
    /// Loudness range (LU) — ffmpeg ebur128 only; nil when ffmpeg absent.
    let loudnessRange: Double?
    /// Native clipping detection (any sample at/above 0 dBFS).
    let isClipping: Bool?
    /// CBR vs VBR — ffprobe only; nil when ffprobe absent or inconclusive.
    let isVBR: Bool?
}

enum ExtendedState: Equatable, Sendable {
    case measuring(progress: Double)
    case ready(ExtendedStats)
}

enum AnalysisStatus: Equatable, Sendable {
    case analyzing
    case ready(MediaInfo)
    case error(String)
}

struct AnalyzedFile: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var status: AnalysisStatus
    var extended: ExtendedState

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.status = .analyzing
        self.extended = .measuring(progress: 0)
    }

    var measuringProgress: Double? {
        if case .measuring(let progress) = extended { return progress }
        return nil
    }

    var info: MediaInfo? {
        if case .ready(let info) = status { return info }
        return nil
    }

    var extendedStats: ExtendedStats? {
        if case .ready(let stats) = extended { return stats }
        return nil
    }

    var errorMessage: String? {
        if case .error(let message) = status { return message }
        return nil
    }

    static func == (lhs: AnalyzedFile, rhs: AnalyzedFile) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.extended == rhs.extended
    }
}
