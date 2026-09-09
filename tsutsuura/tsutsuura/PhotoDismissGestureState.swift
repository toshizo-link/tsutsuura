import Foundation

/// A photo's vertical dismissal owns a gesture only after its initial direction
/// is known. Horizontal or upward starts cannot become a dismissal mid-gesture.
struct PhotoDismissGestureState {
    static let dismissalDistance: CGFloat = 120
    private(set) var isDragging = false
    private(set) var distance: CGFloat = 0

    static func acceptsInitialTranslation(_ translation: CGSize) -> Bool {
        translation.width.isFinite && translation.height.isFinite
            && translation.height > 0
            && translation.height > abs(translation.width) * 1.25
    }

    mutating func begin(translation: CGSize) {
        cancel()
        guard Self.acceptsInitialTranslation(translation) else { return }
        isDragging = true
        update(translation: translation)
    }

    mutating func update(translation: CGSize) {
        guard isDragging else { return }
        distance = translation.height.isFinite ? max(0, translation.height) : 0
    }

    mutating func finish(translation: CGSize) -> Bool {
        guard isDragging else { return false }
        update(translation: translation)
        let shouldDismiss = distance >= Self.dismissalDistance
        cancel()
        return shouldDismiss
    }

    mutating func cancel() {
        isDragging = false
        distance = 0
    }
}
