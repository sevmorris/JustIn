import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor.opacity(0.5))

            VStack(spacing: 8) {
                Text("Drag and drop audio or video files here to analyze them.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("See the Help menu for details on supported formats.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    EmptyStateView()
}
