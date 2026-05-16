import Foundation

/// A passive RMS fingerprint of a file's audio. One value per display bucket,
/// per rendered lane (1 = mono, 2 = stereo L/R). Values are RMS amplitude
/// 0...1, mapped to lane height with no per-file normalization.
struct WaveformData: Sendable, Equatable {
    let lanes: [[Float]]
    let bucketCount: Int

    var isStereo: Bool { lanes.count >= 2 }
}

enum WaveformState: Equatable, Sendable {
    case none
    case rendering(WaveformData)
    case ready(WaveformData)
    case unavailable
}
