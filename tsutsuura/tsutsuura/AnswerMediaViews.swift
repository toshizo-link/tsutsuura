import SwiftUI
import Combine

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(PhotosUI)
import PhotosUI
#endif

#if canImport(UIKit)
import UIKit
#endif

struct AnswerMediaLoader: Sendable {
    private let action: @MainActor @Sendable (AnswerMedia) async throws -> AnswerMediaContent

    init(
        _ action: @escaping @MainActor @Sendable (AnswerMedia) async throws -> AnswerMediaContent
    ) {
        self.action = action
    }

    @MainActor
    func callAsFunction(_ media: AnswerMedia) async throws -> AnswerMediaContent {
        try await action(media)
    }
}

enum AnswerMediaViewError: LocalizedError {
    case unavailable
    case invalidPhoto

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "メディアを読み込めませんでした。"
        case .invalidPhoto:
            return "写真を表示できませんでした。"
        }
    }
}

struct AnswerDraftMediaStrip: View {
    let voiceRecording: AnswerMediaUpload?
    let photos: [AnswerMediaUpload]
    let onRemoveVoice: () -> Void
    let onRemovePhoto: (UUID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let voiceRecording {
                draftAudioChip(voiceRecording)
            }

            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                draftPhotoThumbnail(
                    photo,
                    index: index,
                    total: photos.count
                )
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func draftAudioChip(_ recording: AnswerMediaUpload) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .bold))
                .accessibilityHidden(true)
            Text(Self.durationText(recording.durationMilliseconds))
                .font(TsutsuuraTheme.font(18))
                .lineLimit(1)
            Button(action: onRemoveVoice) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("音声を削除")
        }
        .foregroundStyle(TsutsuuraTheme.ink)
        .padding(.horizontal, 10)
        .frame(height: 54)
        .background(TsutsuuraTheme.cyan.opacity(0.24))
        .overlay(
            Rectangle()
                .stroke(TsutsuuraTheme.cyanDark.opacity(0.8), lineWidth: 2)
        )
        .accessibilityLabel(
            "音声回答 \(Self.durationText(recording.durationMilliseconds))"
        )
    }

    @ViewBuilder
    private func draftPhotoThumbnail(
        _ photo: AnswerMediaUpload,
        index: Int,
        total: Int
    ) -> some View {
        #if canImport(UIKit)
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = UIImage(data: photo.data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(TsutsuuraTheme.skyMuted)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 54, height: 54)
            .clipped()
            .overlay(
                Rectangle()
                    .stroke(TsutsuuraTheme.cyanDark.opacity(0.8), lineWidth: 2)
            )

            Button {
                onRemovePhoto(photo.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 19, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, TsutsuuraTheme.ink.opacity(0.86))
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .accessibilityLabel("写真\(index + 1)／\(total)を削除")
        }
        .accessibilityElement(children: .contain)
        #else
        EmptyView()
        #endif
    }

    private static func durationText(_ durationMilliseconds: Int?) -> String {
        guard let durationMilliseconds else { return "音声" }
        let totalSeconds = max(0, durationMilliseconds / 1_000)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

#if canImport(PhotosUI)
@MainActor
struct AnswerPhotoPickerButton: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let currentPhotoCount: Int
    let onAddPhotos: ([AnswerMediaUpload]) -> Bool
    let onError: (String) -> Void

    @State private var selection: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var importTask: Task<Void, Never>?

    private var remainingPhotoCount: Int {
        max(0, AnswerDraft.maximumPhotoCount - currentPhotoCount)
    }

    var body: some View {
        let importing = isImporting
        let buttonFill = TsutsuuraTheme.actionFill(TsutsuuraTheme.cyan, contrast: contrast)
        PhotosPicker(
            selection: $selection,
            maxSelectionCount: max(1, remainingPhotoCount),
            matching: .images,
            preferredItemEncoding: .automatic
        ) {
            ZStack {
                Rectangle()
                    .fill(TsutsuuraTheme.cyanDark)
                    .offset(y: 5)

                Rectangle()
                    .fill(buttonFill)

                HStack(spacing: 8) {
                    if importing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 21, weight: .bold))
                            .accessibilityHidden(true)
                    }
                    Text(currentPhotoCount == 0 ? "写真" : "写真 \(currentPhotoCount)")
                        .font(TsutsuuraTheme.displayFont(20))
                }
                .foregroundStyle(.white)
            }
            .frame(height: 57)
            .overlay(Rectangle().stroke(TsutsuuraTheme.cyanDark, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .disabled(isImporting || remainingPhotoCount == 0)
        .accessibilityLabel("回答に写真を追加")
        .accessibilityValue("\(currentPhotoCount)枚選択中、最大\(AnswerDraft.maximumPhotoCount)枚")
        .accessibilityIdentifier("add-answer-photos")
        .onChange(of: selection) { _, newSelection in
            guard !newSelection.isEmpty else { return }
            importTask?.cancel()
            importTask = Task {
                await importPhotos(newSelection)
            }
        }
        .onDisappear {
            importTask?.cancel()
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer {
            isImporting = false
            selection = []
        }

        do {
            var uploads: [AnswerMediaUpload] = []
            uploads.reserveCapacity(items.count)
            for (index, item) in items.enumerated() {
                try Task.checkCancellation()
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw AnswerMediaViewError.invalidPhoto
                }
                uploads.append(
                    try AnswerMediaUpload.normalizedPhoto(
                        from: data,
                        preferredFileName: "photo-\(index + 1).jpg"
                    )
                )
            }
            guard !Task.isCancelled else { return }
            _ = onAddPhotos(uploads)
        } catch is CancellationError {
            return
        } catch {
            onError(error.localizedDescription)
        }
    }
}
#endif

struct AnswerMediaGallery: View {
    let media: [AnswerMedia]
    let loadMedia: AnswerMediaLoader
    @State private var selectedPhotoIndex = 0
    @State private var fullScreenSelection: AnswerPhotoSelection?

    private var photos: [AnswerMedia] {
        media.filter { $0.kind == .photo }
    }

    private var audio: AnswerMedia? {
        media.first { $0.kind == .audio }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if !photos.isEmpty {
                ZStack(alignment: .topTrailing) {
                    TabView(selection: $selectedPhotoIndex) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            AuthenticatedAnswerPhoto(
                                media: photo,
                                index: index,
                                total: photos.count,
                                loadMedia: loadMedia
                            )
                            .onTapGesture { openPhoto(at: index) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("タップすると、写真を大きく表示します")
                            .accessibilityAction { openPhoto(at: index) }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))

                    Text("\(selectedPhotoIndex + 1) / \(photos.count)")
                        .font(TsutsuuraTheme.font(17))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(TsutsuuraTheme.ink.opacity(0.82))
                        .padding(8)
                        .accessibilityLabel(
                            "写真\(selectedPhotoIndex + 1)／\(photos.count)"
                        )
                        .accessibilityIdentifier("answer-photo-page-indicator")
                }
                .frame(height: 196)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("回答の写真、\(photos.count)枚。左右にスワイプして表示します")
                .accessibilityIdentifier("answer-photo-gallery")
                .onChange(of: photos.count) { _, count in
                    selectedPhotoIndex = min(selectedPhotoIndex, max(0, count - 1))
                }
            }

            if let audio {
                AnswerAudioButton(media: audio, loadMedia: loadMedia)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fullScreenCover(item: $fullScreenSelection) { selection in
            AnswerPhotoFullscreenGallery(selection: selection, loadMedia: loadMedia) { photoID in
                if let index = photos.firstIndex(where: { $0.id == photoID }) {
                    selectedPhotoIndex = index
                }
            }
        }
    }

    private func openPhoto(at index: Int) {
        guard photos.indices.contains(index) else { return }
        fullScreenSelection = AnswerPhotoSelection(photos: photos, initialIndex: index)
    }
}

/// Snapshot this answer's photos so a feed refresh cannot change an open gallery.
private struct AnswerPhotoSelection: Identifiable {
    let id = UUID()
    let photos: [AnswerMedia]
    let initialIndex: Int
}

private struct AnswerPhotoFullscreenGallery: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let selection: AnswerPhotoSelection
    let loadMedia: AnswerMediaLoader
    let onSelectionChanged: (String) -> Void
    @State private var selectedIndex: Int
    @State private var dismissalGesture = PhotoDismissGestureState()
    @State private var photoOffset: CGFloat = 0
    @State private var closingOpacity: Double = 1
    @State private var isClosing = false
    @State private var horizontalOffset: CGFloat = 0
    @State private var dragDirection: PhotoGalleryDragDirection?
    @GestureState private var photoGestureIsActive = false

    init(
        selection: AnswerPhotoSelection,
        loadMedia: AnswerMediaLoader,
        onSelectionChanged: @escaping (String) -> Void
    ) {
        self.selection = selection
        self.loadMedia = loadMedia
        self.onSelectionChanged = onSelectionChanged
        _selectedIndex = State(initialValue: selection.initialIndex)
    }

    var body: some View {
        GeometryReader { geometry in
            let progress = min(1, photoOffset / max(1, geometry.size.height))
            VStack(spacing: 0) {
                HStack(spacing: 20) {
                    Text("\(selectedIndex + 1) / \(selection.photos.count)")
                        .font(.system(size: 22, weight: .semibold))
                        .accessibilityLabel("写真\(selectedIndex + 1)／\(selection.photos.count)")
                        .accessibilityIdentifier("answer-fullscreen-photo-page-indicator")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: showPhoto(at: selectedIndex + 1)
                            case .decrement: showPhoto(at: selectedIndex - 1)
                            @unknown default: break
                            }
                        }
                    Spacer()
                    TextRaisedButton(
                        title: "閉じる", icon: "xmark", height: 52,
                        fontSize: 20, usesDisplayFont: false
                    ) {
                        closePhoto(playHaptic: false)
                    }
                    .frame(width: 140)
                    .disabled(isClosing)
                    .accessibilityLabel("写真を閉じる")
                    .accessibilityIdentifier("answer-fullscreen-photo-close")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .opacity(closingOpacity)

                GeometryReader { viewport in
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        HStack(spacing: 0) {
                            ForEach(Array(selection.photos.enumerated()), id: \.element.id) { index, photo in
                                AuthenticatedAnswerPhoto(
                                    media: photo,
                                    index: index,
                                    total: selection.photos.count,
                                    loadMedia: loadMedia,
                                    isFullScreen: true
                                )
                                .frame(width: viewport.size.width, height: viewport.size.height)
                                .allowsHitTesting(selectedIndex == index)
                                .accessibilityHidden(selectedIndex != index)
                            }
                        }
                        .offset(x: -CGFloat(selectedIndex) * viewport.size.width
                                + (reduceMotion ? 0 : horizontalOffset))
                        .frame(width: viewport.size.width, height: viewport.size.height, alignment: .leading)
                        .clipped()
                        .offset(y: reduceMotion ? 0 : photoOffset)
                        .scaleEffect(reduceMotion ? 1 : 1 - progress * 0.06)
                        .opacity(closingOpacity)
                    }
                    .frame(width: viewport.size.width, height: viewport.size.height)
                    .contentShape(Rectangle())
                    .highPriorityGesture(photoDrag(
                        pageWidth: viewport.size.width,
                        dismissalHeight: geometry.size.height
                    ))
                    .allowsHitTesting(!isClosing)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("answer-fullscreen-photo-gallery")

                Text(selection.photos.count > 1
                     ? "左右にスワイプして写真を見られます\n下にスワイプすると閉じます"
                     : "下にスワイプすると閉じます")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(20)
                    .opacity(closingOpacity)
            }
            .foregroundStyle(.white)
            .background {
                Color.black
                    .opacity(closingOpacity * (1 - Double(progress) * 0.6))
                    .ignoresSafeArea()
            }

        }
        .presentationBackground(.clear)
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
        .accessibilityAction(.escape) { closePhoto(playHaptic: true) }
        .onChange(of: selectedIndex) { _, index in
            onSelectionChanged(selection.photos[index].id)
        }
        .onChange(of: photoGestureIsActive) { _, isActive in
            if !isActive, dragDirection != nil { restorePhotoPosition() }
        }
    }

    private func photoDrag(pageWidth: CGFloat, dismissalHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .updating($photoGestureIsActive) { _, isActive, _ in isActive = true }
            .onChanged { value in
                guard !isClosing else { return }
                let translation = value.translation
                if dragDirection == nil {
                    if abs(translation.width) > abs(translation.height) * 1.25 {
                        dragDirection = .horizontal
                    } else if PhotoDismissGestureState.acceptsInitialTranslation(translation) {
                        dragDirection = .downward
                        dismissalGesture.begin(translation: translation)
                    } else if -translation.height > abs(translation.width) * 1.25 {
                        dragDirection = .ignored
                    } else {
                        return
                    }
                }
                switch dragDirection {
                case .horizontal:
                    let isBeyondEdge = (selectedIndex == 0 && translation.width > 0)
                        || (selectedIndex == selection.photos.count - 1 && translation.width < 0)
                    horizontalOffset = min(pageWidth, max(-pageWidth, translation.width))
                        * (isBeyondEdge ? 0.2 : 1)
                case .downward:
                    dismissalGesture.update(translation: translation)
                    photoOffset = dismissalGesture.distance
                case .ignored, nil: break
                }
            }
            .onEnded { value in
                guard !isClosing else { return }
                let completedDirection = dragDirection
                dragDirection = nil
                switch completedDirection {
                case .horizontal:
                    let threshold = min(96, max(44, pageWidth * 0.22))
                    let step = value.translation.width < -threshold ? 1
                        : (value.translation.width > threshold ? -1 : 0)
                    showPhoto(at: selectedIndex + step)
                case .downward:
                    if dismissalGesture.finish(translation: value.translation) {
                        closePhoto(playHaptic: true, travelHeight: dismissalHeight)
                    } else {
                        restorePhotoPosition()
                    }
                case .ignored, nil:
                    restorePhotoPosition()
                }
            }
    }

    private func showPhoto(at index: Int) {
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            selectedIndex = min(max(0, index), selection.photos.count - 1)
            horizontalOffset = 0
        }
    }

    private func restorePhotoPosition() {
        guard !isClosing else { return }
        dismissalGesture.cancel()
        dragDirection = nil
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            photoOffset = 0
            horizontalOffset = 0
        }
    }

    private func closePhoto(playHaptic: Bool, travelHeight: CGFloat? = nil) {
        guard !isClosing else { return }
        isClosing = true
        dismissalGesture.cancel()
        if playHaptic { HapticPlayer.play(.selection) }
        guard let travelHeight, !reduceMotion else {
            var transaction = Transaction()
            transaction.disablesAnimations = reduceMotion
            withTransaction(transaction) { dismiss() }
            return
        }
        withAnimation(TsutsuuraMotion.navigation, completionCriteria: .logicallyComplete) {
            photoOffset = travelHeight
            closingOpacity = 0
        } completion: {
            // The photo already followed the finger offscreen. Avoid a second
            // system cover animation after the interactive spring completes.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { dismiss() }
        }
    }
}

private enum PhotoGalleryDragDirection {
    case horizontal
    case downward
    case ignored
}

private struct AuthenticatedAnswerPhoto: View {
    let media: AnswerMedia
    let index: Int
    let total: Int
    let loadMedia: AnswerMediaLoader
    var isFullScreen = false

    @State private var image: Image?
    @State private var failed = false
    @State private var retryCount = 0

    var body: some View {
        ZStack {
            if !isFullScreen {
                TsutsuuraTheme.skyMuted.opacity(0.25)
            }

            if let image {
                GeometryReader { geometry in
                    image
                        .resizable()
                        .aspectRatio(contentMode: isFullScreen ? .fit : .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                // A fill image's intrinsic frame can be taller than its crop.
                // Keep interaction and accessibility on the bounded container.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            } else if failed {
                if isFullScreen {
                    VStack(spacing: 18) {
                        Label("写真を読み込めませんでした", systemImage: "exclamationmark.triangle")
                            .multilineTextAlignment(.center)
                        Button("もう一度読み込む") { retryCount += 1 }
                            .padding(.horizontal, 20)
                            .frame(minHeight: 52)
                            .background(.white.opacity(0.16), in: Capsule())
                    }
                    .font(.system(size: 20))
                    .padding(24)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(TsutsuuraTheme.coral)
                        .accessibilityHidden(true)
                }
            } else {
                ProgressView()
                    .tint(isFullScreen ? .white : TsutsuuraTheme.cyanDark)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: isFullScreen ? .infinity : nil)
        .frame(height: isFullScreen ? nil : 172)
        .clipped()
        .contentShape(Rectangle())
        .overlay {
            if !isFullScreen {
                Rectangle().stroke(TsutsuuraTheme.skyInk.opacity(0.55), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: isFullScreen && failed ? .contain : .ignore)
        .accessibilityLabel(
            failed
                ? "写真\(index + 1)／\(total)を読み込めませんでした"
                : "回答の写真\(index + 1)／\(total)"
        )
        .accessibilityIdentifier("answer-\(isFullScreen ? "fullscreen-" : "")photo-\(index + 1)-of-\(total)")
        .task(id: "\(media.id)-\(retryCount)") {
            await loadPhoto()
        }
    }

    private func loadPhoto() async {
        #if canImport(UIKit)
        failed = false
        do {
            let data = try await AnswerMediaDataCache.shared.data(
                for: media,
                loadMedia: loadMedia
            )
            guard let uiImage = UIImage(data: data) else {
                throw AnswerMediaViewError.invalidPhoto
            }
            guard !Task.isCancelled else { return }
            image = Image(uiImage: uiImage)
            failed = false
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
        #else
        failed = true
        #endif
    }
}

private struct AnswerAudioButton: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let media: AnswerMedia
    let loadMedia: AnswerMediaLoader

    @StateObject private var player = AnswerAudioPlayer()
    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        Button {
            Task {
                await togglePlayback()
            }
        } label: {
            HStack(spacing: 11) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 19, weight: .bold))
                        .accessibilityHidden(true)
                }

                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .bold))
                    .accessibilityHidden(true)

                Text(failed ? "音声を読み込めません" : durationText)
                    .font(TsutsuuraTheme.font(20))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(TsutsuuraTheme.actionFill(
                failed ? TsutsuuraTheme.coral : TsutsuuraTheme.cyan,
                contrast: contrast
            ))
            .overlay(Rectangle().stroke(TsutsuuraTheme.cyanDark, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(player.isPlaying ? "音声回答を一時停止" : "音声回答を再生")
    }

    private var durationText: String {
        guard let durationMilliseconds = media.durationMilliseconds else {
            return "音声回答"
        }
        let totalSeconds = max(0, durationMilliseconds / 1_000)
        return String(format: "音声回答 %d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func togglePlayback() async {
        if player.isReady {
            player.toggle()
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await AnswerMediaDataCache.shared.data(
                for: media,
                loadMedia: loadMedia
            )
            try player.loadAndPlay(data)
            failed = false
        } catch {
            failed = true
        }
    }
}

@MainActor
private final class AnswerMediaDataCache {
    static let shared = AnswerMediaDataCache()

    private let cache = NSCache<NSURL, NSData>()

    private init() {
        cache.countLimit = 40
        cache.totalCostLimit = 50 * 1_024 * 1_024
    }

    func data(
        for media: AnswerMedia,
        loadMedia: AnswerMediaLoader
    ) async throws -> Data {
        if let cached = cache.object(forKey: media.url as NSURL) {
            return cached as Data
        }
        let content = try await loadMedia(media)
        cache.setObject(
            content.data as NSData,
            forKey: media.url as NSURL,
            cost: content.data.count
        )
        return content.data
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

@MainActor
enum AnswerMediaViewCache {
    static func clear() {
        AnswerMediaDataCache.shared.removeAll()
    }
}

@MainActor
private final class AnswerAudioPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false

    #if canImport(AVFoundation)
    private var player: AVAudioPlayer?

    var isReady: Bool {
        player != nil
    }

    func loadAndPlay(_ data: Data) throws {
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.prepareToPlay()
        self.player = player
        player.play()
        isPlaying = true
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if player.currentTime >= player.duration {
                player.currentTime = 0
            }
            player.play()
            isPlaying = true
        }
    }
    #else
    var isReady: Bool { false }
    func loadAndPlay(_ data: Data) throws { throw AnswerMediaViewError.unavailable }
    func toggle() {}
    #endif
}

#if canImport(AVFoundation)
extension AnswerAudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor [weak self] in
            self?.isPlaying = false
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.isPlaying = false
        }
    }
}
#endif
