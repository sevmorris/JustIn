import AppKit
import SwiftUI

/// A determinate `NSProgressIndicator` bar (0...1), sized by the SwiftUI frame.
struct DeterminateBar: NSViewRepresentable {
    var value: Double

    func makeNSView(context: Context) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.isIndeterminate = false
        indicator.style = .bar
        indicator.controlSize = .small
        indicator.minValue = 0
        indicator.maxValue = 1
        indicator.setContentHuggingPriority(.defaultLow, for: .horizontal)
        indicator.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return indicator
    }

    func updateNSView(_ nsView: NSProgressIndicator, context: Context) {
        nsView.doubleValue = min(1, max(0, value))
    }
}
