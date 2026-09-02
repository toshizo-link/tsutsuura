import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum TsutsuuraTheme {
    static let canvas = CGSize(width: 440, height: 956)
    static let fontName = "Kaisotai-Next-UP-B"
    private static let displayFontMinimumSize: CGFloat = 34

    static let ink = Color(hex: 0x2B2B2B)
    static let dot = Color(hex: 0x414141)
    // White text on every interactive fill below clears WCAG AA's 4.5:1
    // contrast threshold. The regular tokens are already suitable when the
    // system's Increase Contrast setting is enabled, so controls do not need
    // a separate color branch that could drift out of sync.
    static let cyan = Color(hex: 0x1F718D)
    static let cyanDark = Color(hex: 0x154B5D)
    static let cyanMuted = Color(hex: 0x466B76)
    static let sky = Color(hex: 0xD7F0F7)
    static let skyInk = Color(hex: 0x3E4E50)
    static let skyMuted = Color(hex: 0x52666A)
    static let green = Color(hex: 0x34752F)
    static let greenDark = Color(hex: 0x24571F)
    static let orange = Color(hex: 0xA94F14)
    static let orangeDark = Color(hex: 0x71340A)
    static let coral = Color(hex: 0xB34B54)
    static let blueAvatar = Color(hex: 0x386EA7)
    static let white = Color.white

    static func font(_ size: CGFloat) -> Font {
        if size < displayFontMinimumSize {
            return bodyFont(size)
        }

        return displayFont(size)
    }

    /// Kaisotai is intentionally limited to large display type. Body copy,
    /// metadata, form labels, and controls use the system Japanese face.
    static func displayFont(_ size: CGFloat) -> Font {
        .custom(
            fontName,
            size: size,
            relativeTo: textStyle(for: size)
        )
    }

    /// A semantic system font that participates in Dynamic Type without
    /// relying on a fixed point size.
    static func bodyFont(_ size: CGFloat) -> Font {
        .system(textStyle(for: size), design: .default)
            .weight(size >= 22 ? .semibold : .regular)
    }

    /// Labeled overload for screens that need an explicit semantic weight.
    static func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(textStyle(for: size), design: .default)
            .weight(weight)
    }

    /// Large codes are critical form content, so keep their glyphs familiar,
    /// monospaced, and tied to a semantic Dynamic Type style.
    static func codeFont() -> Font {
        .system(.largeTitle, design: .monospaced)
            .weight(.bold)
    }

    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 44...:
            return .largeTitle
        case 32..<44:
            return .title
        case 27..<32:
            return .title2
        case 22..<27:
            return .title3
        case 17..<22:
            return .body
        default:
            return .caption
        }
    }
}

enum TsutsuuraMotion {
    /// Fast state changes such as keyboard clearance and compact controls.
    static let quickSpring = Animation.spring(duration: 0.22, bounce: 0.28)

    /// The default navigation and presentation rhythm.
    static let spring = Animation.spring(duration: 0.30, bounce: 0.32)

    /// A slightly larger arrival used for celebratory or full-card reveals.
    static let emphasizedSpring = Animation.spring(duration: 0.38, bounce: 0.38)

    static let pressDown = Animation.spring(duration: 0.08, bounce: 0.08)
    static let pressRelease = Animation.spring(duration: 0.18, bounce: 0.34)

    static func respectingReduceMotion(
        _ reduceMotion: Bool,
        _ animation: Animation = spring
    ) -> Animation? {
        reduceMotion ? nil : animation
    }

    static func buttonSpring(
        isPressed: Bool,
        reduceMotion: Bool
    ) -> Animation? {
        respectingReduceMotion(
            reduceMotion,
            isPressed ? pressDown : pressRelease
        )
    }
}

extension Color {
    init(hex: Int, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

struct TsutsuuraCanvas<Content: View>: View {
    var keepsFullScaleWithKeyboard = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            // GeometryReader can briefly report zero during a transition.
            // Clamp both axes so that the authored canvas never receives an
            // infinite height (which otherwise triggers an invalid-frame
            // warning and can disrupt hit testing during UI transitions).
            let availableWidth = proxy.size.width.isFinite
                && proxy.size.width > 0
                ? proxy.size.width
                : TsutsuuraTheme.canvas.width
            let availableHeight = proxy.size.height.isFinite
                && proxy.size.height > 0
                ? proxy.size.height
                : TsutsuuraTheme.canvas.height
            // Never shrink text or touch targets to make the original 440pt
            // artboard fit. Compact iPhones center-crop the small decorative
            // gutters (the authored content begins at 34pt) while controls
            // retain their real Dynamic Type size and 44pt minimum target.
            // Taller/shorter devices receive their actual safe-area height.
            let canvasHeight = availableHeight

            ZStack {
                TsutsuuraTheme.ink
                content()
                    .frame(
                        width: TsutsuuraTheme.canvas.width,
                        height: canvasHeight
                    )
                    .frame(
                        width: availableWidth,
                        height: availableHeight
                    )
                    .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Only the backdrop extends under system chrome. Interactive content
        // remains inside the status-bar and home-indicator safe areas.
        .background(TsutsuuraTheme.ink.ignoresSafeArea())
        .ignoresSafeArea(
            keepsFullScaleWithKeyboard ? .keyboard : [],
            edges: .bottom
        )
    }
}

struct DottedBackdrop: View {
    var background = TsutsuuraTheme.ink
    var dot = TsutsuuraTheme.dot
    var spacing: CGFloat = 24
    var diameter: CGFloat = 4
    var offset = CGPoint(x: 1, y: 19)

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(background)
            )

            var y = offset.y
            while y < size.height {
                var x = offset.x
                while x < size.width {
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: x,
                                y: y,
                                width: diameter,
                                height: diameter
                            )
                        ),
                        with: .color(dot)
                    )
                    x += spacing
                }
                y += spacing
            }
        }
        .accessibilityHidden(true)
    }
}

struct PaperPanel<Content: View>: View {
    var fill = TsutsuuraTheme.sky
    var border = TsutsuuraTheme.skyInk.opacity(0.55)
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Rectangle()
                .fill(fill)

            UnevenPaperHighlight()
                .fill(.white.opacity(0.32))

            UnevenPaperFold()
                .fill(TsutsuuraTheme.skyInk.opacity(0.08))

            Rectangle()
                .strokeBorder(border, lineWidth: 3)

            content()
        }
    }
}

private struct UnevenPaperHighlight: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: 0, y: min(rect.height * 0.15, 30)))
        path.closeSubpath()
        return path
    }
}

private struct UnevenPaperFold: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - min(rect.height * 0.12, 24)))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct CornerHandle: View {
    var lineRotation: Double

    var body: some View {
        ZStack {
            Image("InputHandleCircle")
                .resizable()
                .frame(width: 20, height: 21)

            Rectangle()
                .fill(Color(hex: 0xD9D9D9))
                .frame(width: 14.7, height: 2.1)
                .rotationEffect(.degrees(lineRotation))

            Rectangle()
                .fill(Color(hex: 0xD9D9D9))
                .frame(width: 14.7, height: 2.1)
                .rotationEffect(.degrees(lineRotation + 90))
        }
        .frame(width: 20, height: 21)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct RaisedButton<Label: View>: View {
    let fill: Color
    let shadow: Color
    var borderHighlight = Color.white.opacity(0.20)
    var height: CGFloat = 68
    var haptic: TsutsuuraHaptic = .selection
    var isSelected = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            HapticPlayer.play(haptic)
            action()
        } label: {
            label()
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(
            RaisedButtonStyle(
                fill: fill,
                shadow: shadow,
                borderHighlight: borderHighlight,
                height: height,
                isSelected: isSelected
            )
        )
    }
}

struct TextRaisedButton: View {
    let title: String
    var icon: String?
    var fill = TsutsuuraTheme.cyan
    var shadow = TsutsuuraTheme.cyanDark
    var height: CGFloat = 68
    var fontSize: CGFloat = 31
    var haptic: TsutsuuraHaptic = .selection
    var isSelected = false
    let action: () -> Void

    var body: some View {
        RaisedButton(
            fill: fill,
            shadow: shadow,
            height: height,
            haptic: haptic,
            isSelected: isSelected,
            action: action
        ) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: fontSize * 0.78, weight: .bold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(TsutsuuraTheme.bodyFont(fontSize))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .accessibilityLabel(title)
    }
}

struct IconTextRaisedButton: View {
    let title: String
    let iconName: String
    let fill: Color
    let shadow: Color
    var height: CGFloat = 78
    let action: () -> Void

    var body: some View {
        RaisedButton(
            fill: fill,
            shadow: shadow,
            height: height,
            action: action
        ) {
            HStack(spacing: 18) {
                Image(iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 43, height: 43)
                    .accessibilityHidden(true)

                Text(title)
                    .font(TsutsuuraTheme.bodyFont(36))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .accessibilityLabel(title)
    }
}

private struct ButtonInsetHighlight: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let capHeight = min(8, max(0, rect.height))
        let sideHeight = max(0, rect.height - capHeight)
        let rightEdge = max(0, rect.width - 3)
        path.addRect(
            CGRect(x: 0, y: 0, width: max(0, rect.width), height: capHeight)
        )
        if sideHeight > 0 {
            path.addRect(
                CGRect(x: 0, y: capHeight, width: 3, height: sideHeight)
            )
            path.addRect(
                CGRect(
                    x: rightEdge,
                    y: capHeight,
                    width: 3,
                    height: sideHeight
                )
            )
        }
        return path
    }
}

private struct RaisedButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    let fill: Color
    let shadow: Color
    let borderHighlight: Color
    let height: CGFloat
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isMechanicallyDown =
            isSelected || (configuration.isPressed && !reduceMotion)
        // The Figma pressed state preserves the 68 pt face, moves it down
        // exactly 5 pt, and removes those 5 pt from the visible extrusion.
        let depth: CGFloat = 5

        ZStack {
            Rectangle()
                .fill(isEnabled ? shadow : Color(hex: 0x343C3E))
                .offset(y: depth)

            ZStack {
                Rectangle()
                    .fill(isEnabled ? fill : Color(hex: 0x566366))

                ButtonInsetHighlight()
                    .fill(borderHighlight)

                configuration.label
            }
            // At rest the base protrudes below the face. Pressing moves the
            // unchanged face over it, so the shadow physically disappears.
            .offset(y: isMechanicallyDown ? depth : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: height)
        // Rectangles greedily accept an unbounded vertical proposal (for
        // example inside the bottom-aligned comment composer). Keep the
        // control at its ideal content height while still allowing a wrapped
        // Dynamic Type title to grow beyond the requested minimum.
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .accessibilityValue(isEnabled ? "" : "利用できません")
        .animation(
            TsutsuuraMotion.buttonSpring(
                isPressed: isMechanicallyDown,
                reduceMotion: reduceMotion
            ),
            value: isMechanicallyDown
        )
    }
}

enum TsutsuuraHaptic {
    case selection
    case success
    case warning
}

@MainActor
enum HapticPlayer {
    static func play(_ haptic: TsutsuuraHaptic) {
        #if canImport(UIKit)
        switch haptic {
        case .selection:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        #endif
    }
}

struct PersonBadge: View {
    let name: String
    var tint = TsutsuuraTheme.coral

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Rectangle()
                    .fill(tint)

                // Draw the decorative envelope directly. Some iOS builds
                // exposed the SF Symbol's internal English name ("Mark
                // Read") even when the Image was hidden and its parent was
                // grouped, so it must not exist in the accessibility tree.
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 25, height: 18)
                    Path { path in
                        path.move(to: CGPoint(x: 1, y: 2))
                        path.addLine(to: CGPoint(x: 12.5, y: 11))
                        path.addLine(to: CGPoint(x: 24, y: 2))
                    }
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 25, height: 18)
                }
                .rotationEffect(.degrees(-8))
                .accessibilityHidden(true)
            }
            .frame(width: 42, height: 42)

            Text(name)
                .font(TsutsuuraTheme.bodyFont(28))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}

struct BusyOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.44)

            VStack(spacing: 24) {
                ZStack {
                    Rectangle()
                        .fill(TsutsuuraTheme.cyanDark)
                        .offset(y: 5)

                    Rectangle()
                        .fill(TsutsuuraTheme.cyan)

                    Image("FigmaPhoneIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 43, height: 43)
                }
                .frame(width: 76, height: 76)
                .scaleEffect(
                    reduceMotion ? 1 : (pulsing ? 1.04 : 0.96)
                )
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 0.52)
                            .repeatForever(autoreverses: true),
                    value: pulsing
                )

                Text("認証中…")
                    .font(TsutsuuraTheme.font(30))
                    .foregroundStyle(.white)
            }
        }
        .onAppear {
            pulsing = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("認証中")
    }
}
