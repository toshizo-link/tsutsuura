import SwiftUI

/// The haptic latch is separate from readiness: retreating cancels the action
/// without making small movements around the threshold buzz repeatedly.
struct HomeBannerPullState {
    static let threshold: CGFloat = 64

    private(set) var distance: CGFloat = 0
    private(set) var isDragging = false
    private var hasSignaledReady = false

    var progress: CGFloat { min(distance / Self.threshold, 1) }
    var isReady: Bool { isDragging && distance >= Self.threshold }

    mutating func begin(at distance: CGFloat) -> Bool {
        cancel()
        isDragging = true
        return update(distance: distance)
    }

    mutating func update(distance: CGFloat) -> Bool {
        guard isDragging else { return false }
        self.distance = distance.isFinite ? max(0, distance) : 0
        guard isReady, !hasSignaledReady else { return false }
        hasSignaledReady = true
        return true
    }

    mutating func finish(at distance: CGFloat) -> Bool {
        guard isDragging else { return false }
        _ = update(distance: distance)
        let shouldReveal = isReady
        cancel()
        return shouldReveal
    }

    mutating func cancel() {
        distance = 0
        isDragging = false
        hasSignaledReady = false
    }
}

struct HomeBannerPullToReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let enabled: Bool
    let contextID: String
    let onReveal: () -> Void
    @State private var pull = HomeBannerPullState()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                -(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, distance in
                guard enabled else { return }
                if pull.update(distance: distance) {
                    HapticPlayer.play(.selection)
                }
            }
            .onScrollPhaseChange { oldPhase, newPhase, context in
                guard enabled else {
                    pull.cancel()
                    return
                }
                let distance = -(context.geometry.contentOffset.y + context.geometry.contentInsets.top)
                if newPhase == .interacting {
                    if pull.begin(at: distance) {
                        HapticPlayer.play(.selection)
                    }
                } else if oldPhase == .interacting {
                    withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion, TsutsuuraMotion.navigation)) {
                        if pull.finish(at: distance) {
                            onReveal()
                            HapticPlayer.play(.success)
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if enabled, pull.isDragging, pull.distance > 8 {
                    HomeBannerPullCue(progress: pull.progress, isReady: pull.isReady)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .opacity(min((pull.distance - 8) / 20, 1))
                        .offset(y: reduceMotion ? 0 : min(pull.distance * 0.1, 10))
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: enabled) { _, _ in pull.cancel() }
            .onChange(of: contextID) { _, _ in pull.cancel() }
            .onDisappear { pull.cancel() }
    }
}

private struct HomeBannerPullCue: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let progress: CGFloat
    let isReady: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(.white.opacity(0.3), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(TsutsuuraTheme.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "arrow.down")
                    .rotationEffect(.degrees(reduceMotion ? 0 : 180 * progress))
                    .opacity(isReady ? 0 : 1)
                Image(systemName: "checkmark")
                    .opacity(isReady ? 1 : 0)
                    .scaleEffect(reduceMotion || isReady ? 1 : 0.6)
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .scaleEffect(reduceMotion || !isReady ? 1 : 1.12)
            .animation(TsutsuuraMotion.respectingReduceMotion(reduceMotion, TsutsuuraMotion.quickSpring), value: isReady)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(isReady ? "指を離すと表示" : "下に引くと表示")
                    .font(.body.weight(.semibold))
                Text("次の質問のお知らせ")
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(TsutsuuraTheme.ink.opacity(0.96))
        .overlay {
            Rectangle().stroke(isReady ? TsutsuuraTheme.cyan : .white.opacity(0.4), lineWidth: 2)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isReady ? "指を離すと次の質問のお知らせを表示" : "下に引くと次の質問のお知らせを表示")
        .accessibilityValue(isReady ? "準備完了" : "引いています")
        .accessibilityIdentifier("home-banner-pull-cue")
    }
}
