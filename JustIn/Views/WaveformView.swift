import SwiftUI

/// Passive waveform fingerprint: muted mirrored RMS fill, no interactivity.
/// Amplitude is normalized per render so the loudest bucket reaches ~90% of
/// the lane height regardless of the file's absolute level (it's a shape
/// fingerprint, not a loudness meter — LUFS communicates loudness).
struct WaveformView: View {
    let state: WaveformState

    private let fillColor = Color.primary.opacity(0.28)
    private let edgeColor = Color.primary.opacity(0.42)
    private let separatorColor = Color.primary.opacity(0.15)

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .none:
            Color.clear
        case .unavailable:
            Text("Waveform unavailable")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .rendering(let data), .ready(let data):
            let gain = normalizationGain(for: data)
            if data.isStereo {
                VStack(spacing: 0) {
                    lane(data.lanes[0], gain: gain, label: "L")
                    Rectangle()
                        .fill(separatorColor)
                        .frame(height: 1)
                    lane(data.lanes[1], gain: gain, label: "R")
                }
            } else {
                lane(data.lanes.first ?? [], gain: gain, label: nil)
            }
        }
    }

    /// Scales the loudest bucket across every lane to 1.0. Near-silent files
    /// keep a gain of 0 so they read as a flat line rather than amplified noise.
    private func normalizationGain(for data: WaveformData) -> Float {
        let peak = data.lanes.reduce(Float(0)) { max($0, $1.max() ?? 0) }
        return peak > 1e-4 ? 1 / peak : 0
    }

    private func lane(_ values: [Float], gain: Float, label: String?) -> some View {
        ZStack(alignment: .topLeading) {
            WaveformShape(values: values, gain: gain)
                .fill(fillColor)
            WaveformShape(values: values, gain: gain)
                .stroke(edgeColor, lineWidth: 1)
            if let label {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

/// Filled shape mirrored vertically around the lane's center axis. `gain`
/// applies per-render normalization; the 0.45 factor keeps a ~5% margin at
/// the top and bottom so a full-scale peak never clips the pane edge.
struct WaveformShape: Shape {
    let values: [Float]
    let gain: Float

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }

        let step = rect.width / CGFloat(values.count)
        let midY = rect.midY
        let scale = rect.height * 0.45

        func excursion(_ value: Float) -> CGFloat {
            CGFloat(min(1, max(0, value * gain))) * scale
        }

        path.move(to: CGPoint(x: 0, y: midY))
        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * step + step / 2
            path.addLine(to: CGPoint(x: x, y: midY - excursion(value)))
        }
        for (index, value) in values.enumerated().reversed() {
            let x = CGFloat(index) * step + step / 2
            path.addLine(to: CGPoint(x: x, y: midY + excursion(value)))
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    WaveformView(state: .ready(WaveformData(
        lanes: [[0.1, 0.4, 0.8, 0.3, 0.6, 0.2, 0.5, 0.9, 0.2],
                [0.2, 0.3, 0.7, 0.4, 0.5, 0.3, 0.6, 0.8, 0.1]],
        bucketCount: 9)))
        .frame(height: 100)
        .padding()
}
