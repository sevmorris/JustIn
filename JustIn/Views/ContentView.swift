import SwiftUI

struct ContentView: View {
    var viewModel: AnalyzerViewModel
    @State private var metadataHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            headerView
            if viewModel.showFFmpegNotice {
                ffmpegNotice
            }
            HStack(spacing: 0) {
                fileListSection
                    .frame(width: 260)

                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1)

                detailSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 680, minHeight: 440)
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.addFiles(urls)
            return !urls.isEmpty
        }
        .alert("JustIn", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    private var headerView: some View {
        HStack {
            if !viewModel.files.isEmpty {
                Text("\(viewModel.files.count) file\(viewModel.files.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.saveReportToDesktop()
            } label: {
                Label("Save Report", systemImage: "square.and.arrow.down")
            }
            .disabled(!viewModel.hasReport)
            .help("Save a text report to the Desktop")

            Button {
                viewModel.removeSelected()
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
            .disabled(viewModel.selectedFileID == nil)

            Button {
                viewModel.clearAll()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .tint(.red)
            .disabled(viewModel.files.isEmpty)
            .keyboardShortcut(.delete, modifiers: [.command, .option])
        }
        .padding()
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.35))
                .frame(height: 1)
        }
    }

    private var ffmpegNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.accentColor)
            Text("ffmpeg not found — true peak and loudness range are unavailable. Install ffmpeg (e.g. `brew install ffmpeg`) to enable them.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Dismiss") {
                viewModel.dismissFFmpegNotice()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.25))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var fileListSection: some View {
        if viewModel.files.isEmpty {
            EmptyStateView()
        } else {
            FileListView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var detailSection: some View {
        if let file = viewModel.selectedFile {
            VStack(alignment: .leading, spacing: 12) {
                Text(file.url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.url.path)

                switch file.status {
                case .analyzing:
                    placeholder(symbol: "waveform", text: "Analyzing…")
                case .ready(let info):
                    if info.hasAudio {
                        ResizableWaveformSplit(
                            defaultsKey: "justInWaveformPanelHeight",
                            topHeight: metadataHeight > 0
                                ? metadataHeight
                                : metadataMinHeight(for: info),
                            topMeasured: metadataHeight > 0,
                            bottomMinHeight: 60,
                            bottomDefaultHeight: 120
                        ) {
                            VStack(spacing: 0) {
                                FileStatsView(info: info, extended: file.extended)
                                    .padding(.bottom, 16)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear.onChange(
                                                of: geo.size.height, initial: true
                                            ) { _, height in
                                                if abs(height - metadataHeight) > 0.5 {
                                                    metadataHeight = height
                                                }
                                            }
                                        }
                                    )
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        } bottom: {
                            GeometryReader { geo in
                                WaveformView(state: viewModel.waveform)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .task(id: WaveformKey(
                                        fileID: file.id,
                                        widthBucket: Int(geo.size.width / 16))
                                    ) {
                                        await viewModel.renderWaveform(
                                            fileID: file.id, width: geo.size.width)
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        FileStatsView(info: info, extended: file.extended)
                        Spacer()
                    }
                case .error(let message):
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.accentColor.opacity(0.6))
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding()
        } else {
            placeholder(symbol: "waveform.badge.magnifyingglass",
                        text: "Select a file to view its details")
        }
    }

    /// Estimated height that keeps every metadata section fully visible, used
    /// as the split's top-pane minimum. FILE + AUDIO + LOUDNESS are always
    /// present here (we're in the hasAudio branch); VIDEO is conditional.
    private func metadataMinHeight(for info: MediaInfo) -> CGFloat {
        let sections = 3 + (info.hasVideo ? 1 : 0)
        return CGFloat(sections) * 70 + CGFloat(sections - 1) * 16 + 8
    }

    private func placeholder(symbol: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.alertMessage != nil },
            set: { if !$0 { viewModel.alertMessage = nil } }
        )
    }
}

/// Restarts waveform rendering when the file changes or the panel is resized
/// past a 16pt step (avoids regenerating on every sub-point resize).
private struct WaveformKey: Equatable {
    let fileID: UUID
    let widthBucket: Int
}

#Preview {
    ContentView(viewModel: AnalyzerViewModel())
}
