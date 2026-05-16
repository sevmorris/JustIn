import SwiftUI

struct FileListView: View {
    var viewModel: AnalyzerViewModel

    var body: some View {
        List(selection: Binding(
            get: { viewModel.selectedFileID },
            set: { viewModel.selectedFileID = $0 }
        )) {
            ForEach(viewModel.files) { file in
                row(for: file)
                    .tag(file.id)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func row(for file: AnalyzedFile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(file.url.lastPathComponent)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)

            switch file.status {
            case .analyzing:
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("Analyzing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .ready(let info):
                Text(summary(for: info))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if info.hasAudio, let progress = file.measuringProgress {
                    HStack(spacing: 6) {
                        DeterminateBar(value: progress)
                            .frame(height: 3)
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    .padding(.top, 1)
                }
            case .error:
                Text("Unreadable")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 2)
    }

    private func summary(for info: MediaInfo) -> String {
        var parts = [info.format]
        if let duration = info.duration {
            parts.append(MediaInfoFormatter.duration(duration))
        }
        if info.videoCodec != nil {
            parts.append("Video")
        } else if let ch = info.channelCount {
            parts.append(MediaInfoFormatter.channels(ch))
        }
        return parts.joined(separator: " · ")
    }
}
