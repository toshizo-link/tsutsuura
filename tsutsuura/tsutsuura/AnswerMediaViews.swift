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
                    .fill(TsutsuuraTheme.cyan)

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
                        .font(TsutsuuraTheme.font(20))
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
    }
}

private struct AuthenticatedAnswerPhoto: View {
    let media: AnswerMedia
    let index: Int
    let total: Int
    let loadMedia: AnswerMediaLoader

    @State private var image: Image?
    @State private var failed = false

    var body: some View {
        ZStack {
            TsutsuuraTheme.skyMuted.opacity(0.25)

            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(TsutsuuraTheme.coral)
                    .accessibilityHidden(true)
            } else {
                ProgressView()
                    .tint(TsutsuuraTheme.cyanDark)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 172)
        .clipped()
        .overlay(Rectangle().stroke(TsutsuuraTheme.skyInk.opacity(0.55), lineWidth: 2))
        .accessibilityLabel(
            failed
                ? "写真\(index + 1)／\(total)を読み込めませんでした"
                : "回答の写真\(index + 1)／\(total)"
        )
        .accessibilityIdentifier("answer-photo-\(index + 1)-of-\(total)")
        .task(id: media.id) {
            await loadPhoto()
        }
    }

    private func loadPhoto() async {
        #if canImport(UIKit)
        do {
            let data = try await AnswerMediaDataCache.shared.data(
                for: media,
                loadMedia: loadMedia
            )
            guard let uiImage = UIImage(data: data) else {
                throw AnswerMediaViewError.invalidPhoto
            }
            image = Image(uiImage: uiImage)
            failed = false
        } catch {
            failed = true
        }
        #else
        failed = true
        #endif
    }
}

private struct AnswerAudioButton: View {
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
            .background(failed ? TsutsuuraTheme.coral : TsutsuuraTheme.cyanMuted)
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
