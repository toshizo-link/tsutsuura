import SwiftUI
import UIKit

/// A small, portable stamp: every cell is one of the app's familiar square dots.
/// The saved value contains exactly 256 zeroes and ones, with no image upload.
struct PersonalMarkEditor: View {
    let displayName: String
    let mark: String?
    let onBack: () -> Void
    let onSave: (String?) async -> Bool
    var isRequiredSetup = false
    var onSavingChanged: (Bool) -> Void = { _ in }

    @State private var cells = Array(repeating: false, count: 256)
    @State private var undoHistory: [[Bool]] = []
    @State private var isErasing = false
    @State private var previousCell: CGPoint?
    @State private var isSaving = false
    @State private var saveFailed = false

    private var hasDrawing: Bool { cells.contains(true) }
    private var paintedCellCount: Int { cells.filter { $0 }.count }

    var body: some View {
        LifecyclePage(title: "あなたのしるし", onBack: onBack, showsBackButton: !isRequiredSetup) {
            if isRequiredSetup {
                Text("はじめに、自分のしるしをかきましょう")
                    .font(TsutsuuraTheme.bodyFont(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("personal-mark-required-title")
            }
            Text("下の四角に、指で好きな形や線をかいてください。つつうらの点でできた、あなただけの「しるし」が名前の横につきます。")
                .font(TsutsuuraTheme.bodyFont(size: 22))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            PaperPanel {
                VStack(spacing: 18) {
                    HStack(spacing: 16) {
                        stampPreview
                            .frame(width: 72, height: 72)
                        Text(displayName)
                            .font(TsutsuuraTheme.displayFont(26))
                            .foregroundStyle(TsutsuuraTheme.ink)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(displayName)のしるし。\(hasDrawing ? "手描きの絵" : "まだかいていません")")

                    Text(hasDrawing ? "かいたしるしを使います" : "指でしるしをかいてください")
                        .font(TsutsuuraTheme.bodyFont(size: 19))
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("personal-mark-current-kind")

                    HStack(spacing: 12) {
                        drawingTool("かく", icon: "pencil.tip", selected: !isErasing) {
                            isErasing = false
                        }
                        .accessibilityIdentifier("personal-mark-draw")
                        drawingTool("消す", icon: "eraser", selected: isErasing) {
                            isErasing = true
                        }
                        .accessibilityIdentifier("personal-mark-erase")
                    }

                    drawingCanvas
                        .aspectRatio(1, contentMode: .fit)

                    HStack(spacing: 12) {
                        Button {
                            guard let previous = undoHistory.popLast() else { return }
                            cells = previous
                        } label: {
                            Label("ひとつ戻す", systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .disabled(undoHistory.isEmpty)
                        .accessibilityIdentifier("personal-mark-undo")

                        Button {
                            saveUndo()
                            cells = Array(repeating: false, count: 256)
                        } label: {
                            Text("全部消す")
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .disabled(!hasDrawing)
                        .accessibilityIdentifier("personal-mark-clear")
                    }
                    .font(TsutsuuraTheme.bodyFont(size: 18, weight: .semibold))
                    .foregroundStyle(TsutsuuraTheme.cyanDark)
                }
                .padding(20)
            }

            Text("丸や線だけでも大丈夫です。あとから「設定」でかき直せます。")
                .font(TsutsuuraTheme.bodyFont(size: 21))
                .foregroundStyle(.white)

        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if saveFailed {
                    Text("保存できませんでした。通信を確認して、もう一度お試しください。")
                        .font(TsutsuuraTheme.bodyFont(size: 20))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("personal-mark-error")
                }
                saveButton
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(TsutsuuraTheme.ink)
        }
        .disabled(isSaving)
        .onAppear {
            if let mark, mark.count == 256, mark.allSatisfy({ $0 == "0" || $0 == "1" }) {
                cells = mark.map { $0 == "1" }
            }
        }
    }

    private var saveButton: some View {
            TextRaisedButton(
                title: isSaving ? "保存しています…" : "このしるしを使う",
                icon: "checkmark",
                height: 68,
                fontSize: 25
            ) {
                guard !isSaving, hasDrawing else { return }
                isSaving = true
                onSavingChanged(true)
                saveFailed = false
                let value = cells.map { $0 ? "1" : "0" }.joined()
                Task {
                    let saved = await onSave(value)
                    isSaving = false
                    onSavingChanged(false)
                    if saved {
                        if !isRequiredSetup { onBack() }
                    } else { saveFailed = true }
                }
            }
            .disabled(isSaving || !hasDrawing)
            .accessibilityHint(hasDrawing ? "かいたしるしを保存します" : "先に四角の中にしるしをかいてください")
            .accessibilityIdentifier("personal-mark-save")
    }

    private var stampPreview: some View {
        ZStack {
            TsutsuuraTheme.blueAvatar
            if hasDrawing {
                Canvas { context, size in
                    paint(cells, into: &context, size: size, showsGrid: false)
                }
                .padding(5)
            } else {
                Image(systemName: "pencil.tip")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }

    private var drawingCanvas: some View {
        ZStack {
            Canvas { context, size in
                paint(cells, into: &context, size: size, showsGrid: true)
            }
            .background(TsutsuuraTheme.ink)
            .overlay(Rectangle().stroke(TsutsuuraTheme.cyanDark, lineWidth: 3))
            .accessibilityHidden(true)

            PersonalMarkTouchSurface(
                isEnabled: !isSaving,
                paintedCellCount: paintedCellCount,
                onBegin: { location, size in
                    guard !isSaving else { return }
                    // A cancelled stroke must never connect to the next one.
                    previousCell = nil
                    saveUndo()
                    draw(at: location, in: size)
                },
                onMove: { location, size in
                    guard !isSaving else { return }
                    draw(at: location, in: size)
                },
                onEnd: { previousCell = nil }
            )
        }
    }

    private func draw(at location: CGPoint, in size: CGSize) {
        let point = CGPoint(
            x: min(15, max(0, floor(location.x / max(size.width, 1) * 16))),
            y: min(15, max(0, floor(location.y / max(size.height, 1) * 16)))
        )
        drawLine(from: previousCell ?? point, to: point)
        previousCell = point
    }

    private func drawingTool(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: selected ? "checkmark.circle.fill" : icon)
                .font(TsutsuuraTheme.bodyFont(size: 22, weight: .semibold))
                .foregroundStyle(selected ? Color.white : TsutsuuraTheme.cyanDark)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(selected ? TsutsuuraTheme.cyanDark : Color.white.opacity(0.7))
                .overlay(Rectangle().stroke(TsutsuuraTheme.cyanDark, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func paint(_ cells: [Bool], into context: inout GraphicsContext, size: CGSize, showsGrid: Bool) {
        let unit = CGSize(width: size.width / 16, height: size.height / 16)
        for index in cells.indices {
            guard cells[index] || showsGrid else { continue }
            let inset: CGFloat = cells[index] ? 0.13 : 0.36
            let rect = CGRect(
                x: (CGFloat(index % 16) + inset) * unit.width,
                y: (CGFloat(index / 16) + inset) * unit.height,
                width: unit.width * (1 - 2 * inset),
                height: unit.height * (1 - 2 * inset)
            )
            context.fill(Path(rect), with: .color(cells[index] ? .white : TsutsuuraTheme.skyMuted))
        }
    }

    private func saveUndo() {
        undoHistory.append(cells)
        if undoHistory.count > 40 { undoHistory.removeFirst() }
    }

    private func drawLine(from start: CGPoint, to end: CGPoint) {
        let steps = Int(max(abs(end.x - start.x), abs(end.y - start.y)))
        for step in 0...max(steps, 1) {
            let fraction = CGFloat(step) / CGFloat(max(steps, 1))
            let x = Int((start.x + (end.x - start.x) * fraction).rounded())
            let y = Int((start.y + (end.y - start.y) * fraction).rounded())
            cells[y * 16 + x] = !isErasing
        }
    }

}

/// Touches that begin on the canvas belong to a stroke, including vertical ones.
/// Giving its recognizer priority over the ancestor scroll pan leaves the rest
/// of the page scrollable without cancelling a stroke after its first dot.
private struct PersonalMarkTouchSurface: UIViewRepresentable {
    let isEnabled: Bool
    let paintedCellCount: Int
    let onBegin: (CGPoint, CGSize) -> Void
    let onMove: (CGPoint, CGSize) -> Void
    let onEnd: () -> Void

    func makeUIView(context: Context) -> PersonalMarkTouchView {
        PersonalMarkTouchView()
    }

    func updateUIView(_ view: PersonalMarkTouchView, context: Context) {
        view.onBegin = onBegin
        view.onMove = onMove
        view.onEnd = onEnd
        view.strokeRecognizer.isEnabled = isEnabled
        view.accessibilityValue = "\(paintedCellCount)マスにかいています"
    }

    static func dismantleUIView(_ view: PersonalMarkTouchView, coordinator: ()) {
        view.strokeRecognizer.isEnabled = false
    }
}

private final class PersonalMarkTouchView: UIView {
    var onBegin: (CGPoint, CGSize) -> Void = { _, _ in }
    var onMove: (CGPoint, CGSize) -> Void = { _, _ in }
    var onEnd: () -> Void = {}
    private weak var owningScrollView: UIScrollView?

    lazy var strokeRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(trackStroke(_:)))
        recognizer.minimumPressDuration = 0
        recognizer.allowableMovement = .greatestFiniteMagnitude
        recognizer.numberOfTouchesRequired = 1
        return recognizer
    }()

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityIdentifier = "personal-mark-canvas"
        accessibilityLabel = "しるしをかく場所"
        accessibilityHint = "指を動かしてかきます。丸や線だけでも大丈夫です。かき直すときは、消すか、ひとつ戻すを選びます。"
        accessibilityTraits = [.allowsDirectInteraction]
        addGestureRecognizer(strokeRecognizer)
    }

    required init?(coder: NSCoder) { return nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        giveCanvasPriorityOverScrolling()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        giveCanvasPriorityOverScrolling()
    }

    private func giveCanvasPriorityOverScrolling() {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView {
                if owningScrollView !== scrollView {
                    scrollView.panGestureRecognizer.require(toFail: strokeRecognizer)
                    owningScrollView = scrollView
                }
                return
            }
            ancestor = view.superview
        }
    }

    @objc private func trackStroke(_ recognizer: UILongPressGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            onBegin(point, bounds.size)
        case .changed:
            onMove(point, bounds.size)
        case .ended:
            onMove(point, bounds.size)
            onEnd()
        case .cancelled, .failed:
            onEnd()
        default:
            break
        }
    }
}
