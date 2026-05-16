import SwiftUI

struct FileStatsView: View {
    let info: MediaInfo
    let extended: ExtendedState

    // Informational indicators (subtle, not traffic-light). `.orange` doubles
    // as the "amber" tier and is distinct from the accent on loudness labels.
    private let okColor = Color.green
    private let warnColor = Color.orange
    private let badColor = Color.red

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("FILE") { fileCards }
            if info.hasAudio {
                section("AUDIO") { audioCards }
                section("LOUDNESS") { loudnessCards }
            }
            if info.hasVideo {
                section("VIDEO") { videoCards }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var fileCards: some View {
        statBlock("FORMAT", info.format)
        statBlock("SIZE", MediaInfoFormatter.fileSize(info.fileSize))
        statBlock("MODIFIED", info.modificationDate.map(MediaInfoFormatter.date) ?? "—")
        statBlock("META", info.metadataSummary ?? "—")
        statBlock("CHAPTERS", chapters)
    }

    @ViewBuilder
    private var audioCards: some View {
        if let sr = info.sampleRate {
            statBlock("SR", MediaInfoFormatter.sampleRate(sr))
        }
        if let ch = info.channelCount {
            statBlock("CH", MediaInfoFormatter.channels(ch))
        }
        if let bd = info.bitDepth, bd > 0 {
            statBlock("BIT", "\(bd)-bit")
        }
        if let codec = info.audioCodec {
            statBlock("AUDIO", codec)
        }
        statBlock("MODE", bitrateMode)
        if let br = info.audioBitRate ?? info.bitRate {
            statBlock("BR", MediaInfoFormatter.bitRate(br))
        }
        if let duration = info.duration {
            statBlock("DUR", MediaInfoFormatter.duration(duration))
        }
    }

    @ViewBuilder
    private var loudnessCards: some View {
        switch extended {
        case .measuring(let progress):
            progressBlock("LUFS", progress)
            progressBlock("TRUE PEAK", progress)
            progressBlock("LRA", progress)
            progressBlock("CLIP", progress)
        case .ready(let stats):
            statBlock("LUFS",
                      stats.integratedLUFS.map { String(format: "%.1f LUFS", $0) } ?? "—",
                      labelColor: Color.accentColor,
                      valueColor: lufsColor(stats.integratedLUFS))
            statBlock("TRUE PEAK",
                      stats.truePeak.map { String(format: "%.1f dBTP", $0) } ?? "—",
                      labelColor: Color.accentColor,
                      valueColor: truePeakColor(stats.truePeak))
            statBlock("LRA",
                      stats.loudnessRange.map { String(format: "%.1f LU", $0) } ?? "—",
                      labelColor: Color.accentColor,
                      valueColor: lraColor(stats.loudnessRange))
            statBlock("CLIP",
                      clipText(stats.isClipping),
                      labelColor: Color.accentColor,
                      valueColor: stats.isClipping == true ? badColor : .primary)
        }
    }

    @ViewBuilder
    private var videoCards: some View {
        if let res = MediaInfoFormatter.resolution(width: info.width, height: info.height) {
            statBlock("RESOLUTION", res)
        }
        statBlock("COLOR SPACE", info.colorSpace ?? "—")
        if let fps = info.frameRate {
            statBlock("FPS", MediaInfoFormatter.frameRate(fps))
        }
        if let codec = info.videoCodec {
            statBlock("VIDEO", codec)
        }
        statBlock("V.BR", info.videoBitRate.map(MediaInfoFormatter.bitRate) ?? "—")
    }

    // MARK: - Loudness color coding (values only)

    private func lufsColor(_ value: Double?) -> Color {
        guard let value else { return .primary }
        if value < -30 || value > -14 { return badColor }
        if value >= -23 && value <= -16 { return okColor }
        return warnColor
    }

    private func truePeakColor(_ value: Double?) -> Color {
        guard let value else { return .primary }
        return value <= -1 ? okColor : badColor
    }

    private func lraColor(_ value: Double?) -> Color {
        guard let value else { return .primary }
        if value > 18 { return badColor }
        if value > 12 { return warnColor }
        return .primary
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ cards: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.7)
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    cards()
                }
            }
        }
    }

    private var bitrateMode: String {
        switch extended {
        case .measuring:
            return "…"
        case .ready(let stats):
            guard let isVBR = stats.isVBR else { return "—" }
            return isVBR ? "VBR" : "CBR"
        }
    }

    private var chapters: String {
        guard let count = info.chapterCount else { return "—" }
        return count == 0 ? "None" : "\(count)"
    }

    private func clipText(_ clipping: Bool?) -> String {
        guard let clipping else { return "—" }
        return clipping ? "Yes" : "No"
    }

    @ViewBuilder
    private func statBlock(
        _ label: String,
        _ value: String,
        labelColor: Color? = nil,
        valueColor: Color = .primary
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            cardLabel(label, color: labelColor)
            Text(value)
                .font(.system(size: 15, weight: .semibold).monospaced())
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .fixedSize()
    }

    private func progressBlock(_ label: String, _ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            cardLabel(label, color: Color.accentColor)
            DeterminateBar(value: progress)
                .frame(width: 60, height: 6)
                .padding(.vertical, 4)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .fixedSize()
    }

    @ViewBuilder
    private func cardLabel(_ label: String, color: Color?) -> some View {
        Group {
            if let color {
                Text(label).foregroundStyle(color)
            } else {
                Text(label).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 8, weight: .semibold))
        .kerning(0.5)
    }
}
