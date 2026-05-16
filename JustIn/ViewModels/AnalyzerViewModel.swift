import CoreGraphics
import Foundation
import Observation

@Observable
@MainActor
final class AnalyzerViewModel {
    var files: [AnalyzedFile] = []
    var selectedFileID: UUID?
    var alertMessage: String?

    private var analysisTasks: [UUID: Task<Void, Never>] = [:]
    private var extendedTasks: [UUID: Task<Void, Never>] = [:]

    /// True once any audio file has been added and ffmpeg is unavailable, until
    /// the user dismisses the note. Drives the one-time banner — true-peak and
    /// loudness-range need ffmpeg; everything else still works without it.
    var showFFmpegNotice = false
    private var ffmpegNoticeDismissed = false

    var ffmpegAvailable: Bool { FFmpegLocator.isAvailable }

    /// Waveform for the currently displayed file. Single shared slot — a new
    /// selection clears it immediately and re-renders progressively.
    var waveform: WaveformState = .none
    private var waveformToken: WaveformToken?

    /// Single source of truth for accepted extensions. Kept in sync with the
    /// CFBundleDocumentTypes list in Info.plist. AVFoundation can't natively
    /// decode ogg/mkv/avi, so they are intentionally excluded.
    static let supportedExtensions: Set<String> = [
        "wav", "wave", "aif", "aiff", "mp3", "m4a", "caf", "flac",
        "mp4", "m4v", "mov"
    ]

    var selectedFile: AnalyzedFile? {
        guard let selectedFileID else { return nil }
        return files.first { $0.id == selectedFileID }
    }

    func addFiles(_ urls: [URL]) {
        let valid = urls.filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
        let skipped = urls.count - valid.count

        if skipped > 0 {
            alertMessage = "\(skipped) file\(skipped == 1 ? "" : "s") skipped — unsupported format. Supported: \(Self.supportedExtensions.sorted().joined(separator: ", "))."
        }

        for url in valid {
            let file = AnalyzedFile(url: url)
            files.append(file)
            if selectedFileID == nil { selectedFileID = file.id }
            analyze(file)
        }
    }

    func dismissFFmpegNotice() {
        ffmpegNoticeDismissed = true
        showFFmpegNotice = false
    }

    func removeSelected() {
        guard let id = selectedFileID else { return }
        cancelTasks(for: id)
        files.removeAll { $0.id == id }
        selectedFileID = files.first?.id
        clearWaveform()
    }

    func clearAll() {
        for id in files.map(\.id) { cancelTasks(for: id) }
        files.removeAll()
        selectedFileID = nil
        clearWaveform()
    }

    private func clearWaveform() {
        waveformToken?.cancel()
        waveformToken = nil
        waveform = .none
    }

    /// Drives the detail-panel waveform. Called from the view's `.task(id:)`,
    /// which restarts (and cancels the prior run) whenever the selected file or
    /// the available pixel width changes.
    func renderWaveform(fileID: UUID, width: CGFloat) async {
        guard let file = files.first(where: { $0.id == fileID }),
              let info = file.info, info.hasAudio else {
            clearWaveform()
            return
        }

        let buckets = max(64, Int(width))
        let lanes = (info.channelCount ?? 1) >= 2 ? 2 : 1

        waveformToken?.cancel()
        let token = WaveformToken()
        waveformToken = token

        let empty = WaveformData(
            lanes: Array(repeating: Array(repeating: 0, count: buckets), count: lanes),
            bucketCount: buckets)
        waveform = .rendering(empty)

        let result = await withTaskCancellationHandler {
            await WaveformGenerator.generate(url: file.url, buckets: buckets, token: token) { partial in
                Task { @MainActor in
                    guard self.waveformToken === token else { return }
                    if case .rendering = self.waveform {
                        self.waveform = .rendering(partial)
                    }
                }
            }
        } onCancel: {
            token.cancel()
        }

        guard waveformToken === token, !token.isCancelled else { return }
        waveform = result.map(WaveformState.ready) ?? .unavailable
    }

    private func cancelTasks(for id: UUID) {
        analysisTasks[id]?.cancel()
        analysisTasks.removeValue(forKey: id)
        extendedTasks[id]?.cancel()
        extendedTasks.removeValue(forKey: id)
    }

    private func analyze(_ file: AnalyzedFile) {
        let task = Task {
            do {
                let info = try await MediaAnalyzer.analyze(url: file.url)
                if let index = files.firstIndex(where: { $0.id == file.id }) {
                    files[index].status = .ready(info)
                    measureExtended(file, info: info)
                }
            } catch {
                if let index = files.firstIndex(where: { $0.id == file.id }) {
                    files[index].status = .error(error.localizedDescription)
                }
            }
            analysisTasks.removeValue(forKey: file.id)
        }
        analysisTasks[file.id] = task
    }

    private func measureExtended(_ file: AnalyzedFile, info: MediaInfo) {
        let hasAudio = info.hasAudio
        if hasAudio, !FFmpegLocator.isAvailable, !ffmpegNoticeDismissed {
            showFFmpegNotice = true
        }
        let id = file.id
        let task = Task {
            let stats = await MediaAnalyzer.extendedStats(
                url: file.url,
                hasAudio: hasAudio,
                duration: info.duration
            ) { progress in
                Task { @MainActor in self.updateMeasuringProgress(id, progress) }
            }
            if let index = files.firstIndex(where: { $0.id == id }) {
                files[index].extended = .ready(stats)
            }
            extendedTasks.removeValue(forKey: id)
        }
        extendedTasks[id] = task
    }

    private func updateMeasuringProgress(_ id: UUID, _ progress: Double) {
        guard let index = files.firstIndex(where: { $0.id == id }),
              case .measuring(let current) = files[index].extended else { return }
        if progress >= 1 || progress - current >= 0.01 {
            files[index].extended = .measuring(progress: progress)
        }
    }

    // MARK: - Report

    var hasReport: Bool {
        files.contains { if case .ready = $0.status { return true }; return false }
    }

    func saveReportToDesktop() {
        let report = formattedReport()
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let destination = desktop.appendingPathComponent("JustIn_Report.txt")
        do {
            try report.write(to: destination, atomically: true, encoding: .utf8)
            alertMessage = "Report saved to:\n\(destination.path)"
        } catch {
            alertMessage = "Failed to save report: \(error.localizedDescription)"
        }
    }

    private func formattedReport() -> String {
        let header = "JustIn Media Analysis Report\n"
            + "Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))\n"
            + String(repeating: "─", count: 50) + "\n\n"
        let body = files.map { file -> String in
            if let info = file.info {
                return MediaInfoFormatter.report(
                    for: file.url.lastPathComponent,
                    info: info,
                    extended: file.extendedStats)
            }
            if let error = file.errorMessage {
                return "\(file.url.lastPathComponent)\n  Error: \(error)"
            }
            return "\(file.url.lastPathComponent)\n  Analyzing…"
        }.joined(separator: "\n\n")
        return header + body
    }
}
