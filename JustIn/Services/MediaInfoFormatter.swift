import Foundation

enum MediaInfoFormatter {
    static func duration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 1000)
        return hours > 0
            ? String(format: "%d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
            : String(format: "%d:%02d.%03d", minutes, seconds, milliseconds)
    }

    static func sampleRate(_ rate: Double) -> String {
        if rate >= 1000 {
            let khz = rate / 1000
            return khz.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f kHz", khz)
                : String(format: "%.1f kHz", khz)
        }
        return String(format: "%.0f Hz", rate)
    }

    static func channels(_ count: Int) -> String {
        switch count {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(count)ch"
        }
    }

    static func channelDescription(_ count: Int) -> String {
        switch count {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1 Surround"
        case 8: return "7.1 Surround"
        default: return "\(count) channels"
        }
    }

    static func bitRate(_ bps: Double) -> String {
        if bps >= 1_000_000 {
            return String(format: "%.2f Mbps", bps / 1_000_000)
        } else if bps >= 1_000 {
            return String(format: "%.0f kbps", bps / 1_000)
        }
        return String(format: "%.0f bps", bps)
    }

    static func fileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    static func frameRate(_ fps: Double) -> String {
        let commonRates: [(Double, String)] = [
            (23.976, "23.976 (Film)"),
            (24.0, "24"),
            (25.0, "25 (PAL)"),
            (29.97, "29.97 (NTSC)"),
            (30.0, "30"),
            (50.0, "50"),
            (59.94, "59.94"),
            (60.0, "60"),
            (120.0, "120"),
        ]
        for (rate, label) in commonRates where abs(fps - rate) < 0.01 {
            return label
        }
        return String(format: "%.2f", fps)
    }

    static func resolution(width: Int?, height: Int?) -> String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return "\(width) × \(height)"
    }

    static func date(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    static func report(for fileName: String, info: MediaInfo, extended: ExtendedStats?) -> String {
        var lines = [fileName]
        if let value = info.duration {
            lines.append("  Duration:    \(duration(value))")
        }
        if let value = info.sampleRate {
            lines.append("  Sample Rate: \(sampleRate(value))")
        }
        if let value = info.channelCount {
            lines.append("  Channels:    \(value) (\(channelDescription(value)))")
        }
        if let value = info.bitDepth, value > 0 {
            lines.append("  Bit Depth:   \(value)-bit")
        }
        if let value = info.audioCodec {
            lines.append("  Audio Codec: \(value)")
        }
        if let value = info.videoCodec {
            lines.append("  Video Codec: \(value)")
        }
        if let res = resolution(width: info.width, height: info.height) {
            lines.append("  Resolution:  \(res)")
        }
        if let value = info.colorSpace {
            lines.append("  Color Space: \(value)")
        }
        if let value = info.frameRate {
            lines.append("  Frame Rate:  \(frameRate(value)) fps")
        }
        if info.hasVideo, info.hasAudio {
            lines.append("  Audio Rate:  \(info.audioBitRate.map(bitRate) ?? "—")")
            lines.append("  Video Rate:  \(info.videoBitRate.map(bitRate) ?? "—")")
        } else if let value = info.bitRate {
            lines.append("  Bitrate:     \(bitRate(value))")
        }
        if let value = extended?.isVBR {
            lines.append("  Rate Mode:   \(value ? "VBR" : "CBR")")
        }
        lines.append("  File Size:   \(fileSize(info.fileSize))")
        if let value = info.modificationDate {
            lines.append("  Modified:    \(date(value))")
        }
        lines.append("  Metadata:    \(info.metadataSummary ?? "—")")
        if let count = info.chapterCount {
            lines.append("  Chapters:    \(count == 0 ? "None" : "\(count)")")
        }
        if info.hasAudio {
            let lufs = extended?.integratedLUFS.map { String(format: "%.1f LUFS", $0) } ?? "—"
            let tp = extended?.truePeak.map { String(format: "%.1f dBTP", $0) } ?? "—"
            let lra = extended?.loudnessRange.map { String(format: "%.1f LU", $0) } ?? "—"
            let clip = extended?.isClipping.map { $0 ? "Yes" : "No" } ?? "—"
            lines.append("  Loudness:    \(lufs)")
            lines.append("  True Peak:   \(tp)")
            lines.append("  Loud. Range: \(lra)")
            lines.append("  Clipping:    \(clip)")
        }
        return lines.joined(separator: "\n")
    }
}
