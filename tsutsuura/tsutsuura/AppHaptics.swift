import Foundation

#if os(iOS)
import CoreHaptics
import UIKit
#endif

@MainActor
protocol HapticProviding: AnyObject {
    func selection()
    func impact()
    func success()
    func error()
}

@MainActor
final class LiveHaptics: HapticProviding {
    #if os(iOS)
    private var isSupported: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }
    #endif

    func selection() {
        #if os(iOS)
        guard isSupported else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }

    func impact() {
        #if os(iOS)
        guard isSupported else { return }
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    func success() {
        notification(.success)
    }

    func error() {
        notification(.error)
    }

    #if os(iOS)
    private func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isSupported else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
    #endif
}

@MainActor
final class NoopHaptics: HapticProviding {
    func selection() {}
    func impact() {}
    func success() {}
    func error() {}
}
