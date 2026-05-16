import AppKit
import SwiftUI

/// A native top/bottom `NSSplitView`: metadata on top, waveform on the bottom.
/// The metadata pane holds its content height (high holding priority); the
/// waveform pane absorbs window resizing and is the one the divider drives.
/// The waveform height is persisted to UserDefaults and restored next launch.
struct ResizableWaveformSplit<Top: View, Bottom: View>: NSViewControllerRepresentable {
    let defaultsKey: String
    /// Metadata content height: the measured value once known, otherwise an
    /// estimate. Used as the top pane's minimum (can't be collapsed) and for
    /// the flush default position.
    let topHeight: CGFloat
    let topMeasured: Bool
    let bottomMinHeight: CGFloat
    let bottomDefaultHeight: CGFloat
    let top: Top
    let bottom: Bottom

    init(
        defaultsKey: String,
        topHeight: CGFloat,
        topMeasured: Bool,
        bottomMinHeight: CGFloat = 60,
        bottomDefaultHeight: CGFloat = 120,
        @ViewBuilder top: () -> Top,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.defaultsKey = defaultsKey
        self.topHeight = topHeight
        self.topMeasured = topMeasured
        self.bottomMinHeight = bottomMinHeight
        self.bottomDefaultHeight = bottomDefaultHeight
        self.top = top()
        self.bottom = bottom()
    }

    func makeNSViewController(context: Context) -> WaveformSplitViewController {
        let topHC = NSHostingController(rootView: top)
        let bottomHC = NSHostingController(rootView: bottom)
        // No intrinsic-size constraints on the waveform pane: the split view's
        // frame fully drives it so it fills all four edges and grows/shrinks
        // with the divider.
        bottomHC.sizingOptions = []

        let controller = WaveformSplitViewController()
        controller.defaultsKey = defaultsKey
        controller.bottomMinHeight = bottomMinHeight
        controller.bottomDefaultHeight = bottomDefaultHeight
        controller.topHeight = topHeight
        controller.topMeasured = topMeasured
        controller.splitView.isVertical = false
        controller.splitView.dividerStyle = .thin

        let topItem = NSSplitViewItem(viewController: topHC)
        topItem.canCollapse = false
        topItem.minimumThickness = topHeight
        // High priority: metadata holds its size; it neither shrinks nor grows
        // when the divider is dragged or the window resizes.
        topItem.holdingPriority = .defaultHigh

        let bottomItem = NSSplitViewItem(viewController: bottomHC)
        bottomItem.canCollapse = false
        bottomItem.minimumThickness = bottomMinHeight
        // Low priority: the waveform is the flexible pane the divider drives.
        bottomItem.holdingPriority = .defaultLow

        controller.addSplitViewItem(topItem)
        controller.addSplitViewItem(bottomItem)

        context.coordinator.topHC = topHC
        context.coordinator.bottomHC = bottomHC
        return controller
    }

    func updateNSViewController(_ controller: WaveformSplitViewController, context: Context) {
        context.coordinator.topHC?.rootView = top
        context.coordinator.bottomHC?.rootView = bottom
        controller.topHeight = topHeight
        controller.topMeasured = topMeasured
        if controller.splitViewItems.count == 2 {
            controller.splitViewItems[0].minimumThickness = topHeight
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var topHC: NSHostingController<Top>?
        var bottomHC: NSHostingController<Bottom>?
    }
}

final class WaveformSplitViewController: NSSplitViewController {
    var defaultsKey = "justInWaveformPanelHeight"
    var topHeight: CGFloat = 200
    var topMeasured = false
    var bottomMinHeight: CGFloat = 60
    var bottomDefaultHeight: CGFloat = 120

    private var didInitialPosition = false
    private var measuredFlushApplied = false
    private var restoredSavedValue = false
    private var lastPersistedHeight: CGFloat = -1

    override func viewDidLayout() {
        super.viewDidLayout()
        guard splitViewItems.count == 2 else { return }

        let total = splitView.bounds.height
        guard total > 1 else { return }
        let divider = splitView.dividerThickness

        if !didInitialPosition {
            didInitialPosition = true
            let saved = UserDefaults.standard.double(forKey: defaultsKey)
            if saved >= Double(bottomMinHeight) {
                restoredSavedValue = true
                applyBottom(CGFloat(saved), total: total, divider: divider)
            } else {
                // Flush default: top hugs its content, waveform takes the rest.
                applyBottom(max(bottomDefaultHeight, total - topHeight - divider),
                            total: total, divider: divider)
            }
            return
        }

        // Once the real metadata height is measured, tighten once so the
        // divider sits flush below the content with no trailing dead space.
        if topMeasured, !measuredFlushApplied, !restoredSavedValue {
            measuredFlushApplied = true
            applyBottom(max(bottomDefaultHeight, total - topHeight - divider),
                        total: total, divider: divider)
        }

        // Persist the live waveform height (the only thing the divider moves).
        let height = splitViewItems[1].viewController.view.bounds.height
        if height > 0, abs(height - lastPersistedHeight) >= 1 {
            lastPersistedHeight = height
            UserDefaults.standard.set(Double(height), forKey: defaultsKey)
        }
    }

    private func applyBottom(_ desired: CGFloat, total: CGFloat, divider: CGFloat) {
        let upperBound = max(bottomMinHeight, total - divider - 1)
        let clamped = min(max(desired, bottomMinHeight), upperBound)
        splitView.setPosition(total - clamped - divider, ofDividerAt: 0)
    }
}
