import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                section("Overview") {
                    text("""
                    JustIn is a media file analyzer for macOS. Drop audio or video \
                    files onto the window and JustIn reports their technical \
                    properties — duration, sample rate, channels, codecs, frame \
                    rate, bitrate, and file size.
                    """)
                }

                dividerRow

                section("Quick Start") {
                    steps([
                        "Drag audio or video files onto the window.",
                        "Select a file in the list to view its details.",
                        "Click Save Report to write a text summary to your Desktop."
                    ])
                }

                section("Opening Files") {
                    text("""
                    You can also open files from Finder using “Open With → JustIn”, \
                    or pass file paths as command-line arguments.
                    """)
                }

                dividerRow

                section("Supported Formats") {
                    text("WAV, WAVE, AIF, AIFF, MP3, M4A, CAF, FLAC, MP4, M4V, MOV.")
                    text("""
                    Analysis uses AVFoundation. Formats it cannot natively decode \
                    (such as OGG, MKV, and AVI) are not supported.
                    """)
                }

                dividerRow

                VStack(alignment: .leading, spacing: 6) {
                    Text("If JustIn saves you time, consider buying me a coffee.")
                        .fixedSize(horizontal: false, vertical: true)
                    Link("ko-fi.com/sevmo", destination: URL(string: "https://ko-fi.com/sevmo")!)
                        .font(.body)
                }

                Spacer()
            }
            .padding(30)
        }
        .frame(width: 520, height: 560)
    }

    // MARK: - Components

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("JustIn Help")
                .font(.largeTitle.bold())
            Text("Media File Analyzer for macOS")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var dividerRow: some View {
        Divider()
            .padding(.vertical, 4)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())
            content()
        }
    }

    private func text(_ string: String) -> some View {
        Text(string)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func steps(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.body.bold())
                        .frame(width: 20, alignment: .trailing)
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#Preview {
    HelpView()
}
