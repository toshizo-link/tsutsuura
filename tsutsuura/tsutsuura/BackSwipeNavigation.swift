import SwiftUI

/// Overlay the stable navigation root's leading edge, outside the changing page.
/// This narrow touch surface is a sibling of the page's ScrollView, so an edge
/// swipe never reaches its scrolling recognizer, even while moving diagonally.
struct BackSwipeNavigation: View {
    let enabled: Bool
    let onBack: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 24)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onEnded { value in
                        guard enabled, value.translation.width >= 72 else { return }
                        onBack()
                    }
            )
            .allowsHitTesting(enabled)
            .accessibilityHidden(true)
    }
}
