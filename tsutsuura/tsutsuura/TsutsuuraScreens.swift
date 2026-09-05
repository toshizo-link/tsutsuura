import SwiftUI
import UIKit

enum HomeTab: Hashable {
    case family
    case profile
}

struct LoginScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var phoneNumber: String
    let isLoading: Bool
    let onBack: () -> Void
    let onPhoneAuthentication: () -> Void
    @FocusState private var isPhoneFieldFocused: Bool

    var body: some View {
        LifecyclePage(
            title: "以前のアカウントに戻る",
            onBack: {
                isPhoneFieldFocused = false
                onBack()
            }
        ) {
            VStack(spacing: 10) {
                TsutsuuraWordmark()
                Text("登録済みの電話番号へ、6桁の確認番号を送ります。")
                    .font(TsutsuuraTheme.bodyFont(size: 21))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 22)

            PaperPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("電話番号")
                        .font(TsutsuuraTheme.bodyFont(size: 20, weight: .bold))
                        .foregroundStyle(TsutsuuraTheme.ink)
                    TextField("例：09012345678", text: $phoneNumber)
                        .font(TsutsuuraTheme.bodyFont(size: 26))
                        .foregroundStyle(TsutsuuraTheme.ink)
                        .tsutsuuraPhoneInputTraits()
                        .focused($isPhoneFieldFocused)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 64)
                        .background(.white.opacity(0.72))
                        .overlay(Rectangle().stroke(TsutsuuraTheme.skyInk, lineWidth: 2))
                        .accessibilityLabel("電話番号")
                        .accessibilityIdentifier("returning-phone-input")
                        .onChange(of: phoneNumber) { _, value in
                            if value.count > 32 {
                                phoneNumber = String(value.prefix(32))
                            }
                        }
                    Text("未登録の番号から新しいアカウントを自動作成することはありません。家族を新しく作る場合は前の画面から始めてください。")
                        .font(TsutsuuraTheme.bodyFont(size: 16))
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }

            TextRaisedButton(
                title: isLoading ? "送信中…" : "確認番号を送る",
                icon: "message.fill",
                height: 70,
                fontSize: 25,
                action: authenticate
            )
            .disabled(
                !PhoneNumberValidation.isPlausible(phoneNumber) || isLoading
            )
            .accessibilityIdentifier("returning-phone-submit")

            if isLoading {
                ProgressView("送信しています…")
                    .font(TsutsuuraTheme.bodyFont(size: 18))
                    .foregroundStyle(.white)
                    .tint(.white)
            }
        }
        .animation(
            TsutsuuraMotion.respectingReduceMotion(
                reduceMotion,
                TsutsuuraMotion.quickSpring
            ),
            value: isPhoneFieldFocused
        )
        .animation(
            TsutsuuraMotion.respectingReduceMotion(
                reduceMotion,
                TsutsuuraMotion.quickSpring
            ),
            value: isLoading
        )
        .accessibilityElement(children: .contain)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("閉じる") {
                    isPhoneFieldFocused = false
                }
                .accessibilityIdentifier("dismiss-phone-keyboard")
            }
        }
    }

    private func authenticate() {
        isPhoneFieldFocused = false
        onPhoneAuthentication()
    }
}

struct SMSVerificationScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let phoneNumber: String
    @Binding var code: String
    let isLoading: Bool
    let onBack: () -> Void
    let onResend: () -> Void
    let onVerify: () -> Void
    var confirmationTitle = "ログイン"
    var expiresAt: Date? = nil
    var resendAvailableAt: Date? = nil
    var canReplayExpiredAttempt = false

    @FocusState private var isCodeFocused: Bool

    private var isVerificationDisabled: Bool {
        code.count != 6 || isLoading
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            LifecyclePage(title: "確認番号", onBack: goBack) {
                Text("\(phoneNumber)へ送った6桁の番号を入力してください。")
                    .font(TsutsuuraTheme.bodyFont(size: 21))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PaperPanel {
                    VStack(spacing: 12) {
                        TextField("6桁の確認番号", text: $code)
                            .font(TsutsuuraTheme.bodyFont(size: 32))
                            .foregroundStyle(TsutsuuraTheme.ink)
                            .tsutsuuraOTPInputTraits()
                            .multilineTextAlignment(.center)
                            .focused($isCodeFocused)
                            .onChange(of: code) { _, newValue in
                                code = NumericInputValidation.asciiDigits(
                                    in: newValue,
                                    maximum: 6
                                )
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 72)
                            .background(.white.opacity(0.72))
                            .overlay(Rectangle().stroke(TsutsuuraTheme.skyInk, lineWidth: 2))
                            .accessibilityLabel("確認番号")
                            .accessibilityIdentifier("verification-code-input")

                        if let expiresAt {
                            Text(expiryText(now: timeline.date, expiresAt: expiresAt))
                                .font(TsutsuuraTheme.bodyFont(size: 17))
                                .foregroundStyle(
                                    timeline.date >= expiresAt
                                        ? TsutsuuraTheme.coral
                                        : TsutsuuraTheme.skyInk
                                )
                                .accessibilityIdentifier("otp-expiry-countdown")

                            if canReplayExpiredAttempt,
                               timeline.date >= expiresAt {
                                Text("前回「確認する」を押したあとに通信が途切れた場合は、同じ6桁の番号を入力すると結果を復旧できます。それ以外は確認番号を再送してください。")
                                    .font(TsutsuuraTheme.bodyFont(size: 16))
                                    .foregroundStyle(TsutsuuraTheme.skyInk)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier(
                                        "otp-interrupted-recovery-hint"
                                    )
                            }
                        }
                    }
                    .padding(24)
                }

                TextRaisedButton(
                    title: isLoading ? "確認中…" : confirmationTitle,
                    icon: "checkmark",
                    height: 68,
                    fontSize: 26,
                    haptic: .success,
                    action: verify
                )
                .disabled(
                    isVerificationDisabled
                        || (
                            !canReplayExpiredAttempt
                                && expiresAt.map { timeline.date >= $0 } == true
                        )
                )
                .accessibilityIdentifier("verify-code-button")

                VStack(spacing: 8) {
                    Text("SMSが届かない場合")
                        .font(TsutsuuraTheme.bodyFont(size: 18))
                        .foregroundStyle(.white)
                    Button(resendTitle(now: timeline.date)) {
                        code = ""
                        onResend()
                    }
                    .font(TsutsuuraTheme.bodyFont(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(Rectangle().stroke(.white, lineWidth: 2))
                    .disabled(
                        isLoading
                            || resendAvailableAt.map { timeline.date < $0 } == true
                    )
                    .accessibilityIdentifier("resend-otp-button")
                }
            }
        }
        .animation(
            TsutsuuraMotion.respectingReduceMotion(
                reduceMotion,
                TsutsuuraMotion.quickSpring
            ),
            value: isCodeFocused
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("閉じる") {
                    isCodeFocused = false
                }
                .accessibilityIdentifier("dismiss-code-keyboard")
            }
        }
    }

    private func expiryText(now: Date, expiresAt: Date) -> String {
        let seconds = max(0, Int(expiresAt.timeIntervalSince(now)))
        guard seconds > 0 else { return "確認番号の期限が切れました。再送してください。" }
        return "有効期限 あと\(seconds / 60)分\(seconds % 60)秒"
    }

    private func resendTitle(now: Date) -> String {
        guard let resendAvailableAt,
              resendAvailableAt > now else { return "確認番号を再送" }
        return "あと\(Int(resendAvailableAt.timeIntervalSince(now).rounded(.up)))秒で再送できます"
    }

    private func goBack() {
        isCodeFocused = false
        onBack()
    }

    private func verify() {
        guard !isVerificationDisabled else { return }
        isCodeFocused = false
        onVerify()
    }
}

struct HomeScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    let feed: HomeFeed
    let history: [Answer]
    let currentUserID: String
    @Binding var selectedTab: HomeTab
    let onQuestion: () -> Void
    let onSettings: () -> Void
    let onLike: (Answer) -> Void
    let onComments: (Answer) -> Void
    let loadMedia: AnswerMediaLoader
    var isLoadingFamily = false
    var isLoadingHistory = false
    var hasMoreHistory = false
    var isLoadingMoreHistory = false
    var hasActiveHistoryFilters = false
    var currentHistorySearchText = ""
    var onHistorySearch: ((String) -> Void)? = nil
    var onHistoryFilters: (() -> Void)? = nil
    var onHistoryJumpToToday: (() -> Void)? = nil
    var onLoadMoreHistory: (() -> Void)? = nil
    var hasMoreFamilyAnswers = false
    var isLoadingMoreFamilyAnswers = false
    var onLoadMoreFamilyAnswers: (() -> Void)? = nil

    @State private var historySearchText = ""
    @State private var searchTask: Task<Void, Never>?
    @AppStorage("dismissed-upcoming-questions") private var dismissedUpcomingQuestions = Data()
    @FocusState private var isHistorySearchFocused: Bool

    private var bannerAccountKey: String {
        "\(currentUserID):\(feed.family?.id ?? "")"
    }

    private var dismissedBanners: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: dismissedUpcomingQuestions)) ?? [:]
    }

    private var questionBannerKey: String {
        guard let question = feed.todayQuestion else { return "" }
        return "\(question.id):\(question.publishedOn)"
    }

    private var showsQuestionBanner: Bool {
        guard let question = feed.todayQuestion, question.answer == nil else { return false }
        return question.isAvailable != false || dismissedBanners[bannerAccountKey] != questionBannerKey
    }

    private var canRevealUpcomingQuestion: Bool {
        feed.todayQuestion?.isAvailable == false
            && feed.todayQuestion?.answer == nil
            && !showsQuestionBanner
    }

    private func dismissUpcomingQuestion() {
        guard feed.todayQuestion?.isAvailable == false, showsQuestionBanner else { return }
        HapticPlayer.play(.selection)
        var dismissals = dismissedBanners
        dismissals[bannerAccountKey] = questionBannerKey
        saveBannerDismissals(dismissals)
    }

    private func revealUpcomingQuestion() {
        guard canRevealUpcomingQuestion else { return }
        var dismissals = dismissedBanners
        dismissals.removeValue(forKey: bannerAccountKey)
        saveBannerDismissals(dismissals)
    }

    private func saveBannerDismissals(_ dismissals: [String: String]) {
        if let data = try? JSONEncoder().encode(dismissals) {
            withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion, TsutsuuraMotion.navigation)) {
                dismissedUpcomingQuestions = data
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let question = feed.todayQuestion, showsQuestionBanner {
                NewQuestionHero(
                    question: question,
                    tint: TsutsuuraTheme.cyan,
                    onQuestion: onQuestion,
                    onDismiss: dismissUpcomingQuestion
                )
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            GeometryReader { viewport in
                ZStack(alignment: .topLeading) {
                    ForEach([HomeTab.family, .profile], id: \.self) { tab in
                        timeline(for: tab)
                            .frame(width: viewport.size.width, height: viewport.size.height)
                            .offset(x: tabOffset(tab) * viewport.size.width)
                            .allowsHitTesting(selectedTab == tab)
                            .accessibilityHidden(selectedTab != tab)
                    }
                }
                .clipped()
            }
            BottomNavigation(selectedTab: Binding(
                get: { selectedTab },
                set: { tab in
                    // Resign while the field is still visible. Once its page
                    // moves away UIKit can retain focus and reopen the keyboard
                    // when that mounted page returns, despite a FocusState reset.
                    dismissHistorySearchKeyboard()
                    selectedTab = tab
                }
            ))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .animation(TsutsuuraMotion.respectingReduceMotion(reduceMotion, TsutsuuraMotion.navigation), value: selectedTab)
        .onAppear { historySearchText = currentHistorySearchText }
        .onChange(of: currentHistorySearchText) { _, value in
            historySearchText = value
        }
        .onChange(of: selectedTab) { _, _ in
            dismissHistorySearchKeyboard()
        }
        .onDisappear { searchTask?.cancel() }
        .preference(key: TsutsuuraTopBackdropTintKey.self,
                    value: showsQuestionBanner ? TsutsuuraTheme.cyan : nil)
    }

    private func tabOffset(_ tab: HomeTab) -> CGFloat {
        CGFloat((tab == .family ? 0 : 1) - (selectedTab == .family ? 0 : 1))
    }

    private func timeline(for tab: HomeTab) -> some View {
        let visibleAnswers = tab == .family ? feed.answers : history
        return ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    if tab == .family {
                        FamilyProgress(
                            progress: FamilyAnswerProgress(feed: feed),
                            topPadding: feed.todayQuestion?.answer == nil ? 0 : 16
                        )
                    } else {
                        VStack(spacing: 14) {
                            let headerLayout = dynamicTypeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                : AnyLayout(HStackLayout(spacing: 16))
                            headerLayout {
                                Text("過去の回答")
                                    .font(TsutsuuraTheme.displayFont(31))
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityAddTraits(.isHeader)
                                TextRaisedButton(
                                    title: "設定",
                                    fill: TsutsuuraTheme.cyan,
                                    shadow: TsutsuuraTheme.cyanDark,
                                    height: 62,
                                    fontSize: 27,
                                    action: onSettings
                                )
                                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 105)
                            }

                            if onHistorySearch != nil {
                                HStack(spacing: 10) {
                                    TextField(
                                        "質問や回答を検索",
                                        text: $historySearchText,
                                        prompt: Text("質問や回答を検索")
                                            .foregroundStyle(TsutsuuraTheme.skyMuted)
                                    )
                                        .font(TsutsuuraTheme.bodyFont(size: 20))
                                        .foregroundStyle(TsutsuuraTheme.ink)
                                        .focused($isHistorySearchFocused)
                                        .submitLabel(.search)
                                        .onSubmit {
                                            searchNow()
                                        }
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: 54)
                                        .background(TsutsuuraTheme.sky)
                                        .overlay(Rectangle().stroke(TsutsuuraTheme.skyInk, lineWidth: 2))
                                        .accessibilityIdentifier("history-search-field")
                                        .onChange(of: historySearchText) { _, value in
                                            let clamped = UnicodeTextValidation.clamped(
                                                value,
                                                maximumLength: HistoryQuery.maximumSearchCharacterCount
                                            )
                                            if clamped != value { historySearchText = clamped }
                                            searchTask?.cancel()
                                            searchTask = Task { @MainActor in
                                                do { try await Task.sleep(for: .milliseconds(350)) }
                                                catch { return }
                                                onHistorySearch?(clamped)
                                            }
                                        }

                                    Button {
                                        searchNow()
                                    } label: {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 54, height: 54)
                                            .background(TsutsuuraTheme.actionFill(TsutsuuraTheme.cyan, contrast: contrast))
                                            .accessibilityHidden(true)
                                    }
                                    .accessibilityLabel("履歴を検索")
                                }
                            }

                            if hasActiveHistoryFilters {
                                Button {
                                    historySearchText = ""
                                    searchNow()
                                } label: {
                                    Label("すべての回答に戻る", systemImage: "xmark.circle.fill")
                                        .font(TsutsuuraTheme.bodyFont(20))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                }
                                .accessibilityIdentifier("history-clear-search")
                            }
                        }
                        .padding(.horizontal, 34)
                        .padding(.top, 8)
                    }

                    if visibleAnswers.isEmpty && !(tab == .family ? isLoadingFamily : isLoadingHistory) {
                        EmptyFeedState(
                            isFamily: tab == .family,
                            hasActiveFilters: tab == .profile && hasActiveHistoryFilters
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 32)
                    } else {
                        ForEach(
                            Array(visibleAnswers.enumerated()),
                            id: \.element.id
                        ) { index, answer in
                            AnswerCard(
                                answer: answer,
                                actionMode: tab == .family
                                    ? .family
                                    : .profile,
                                canLike: answer.author.id != currentUserID,
                                onLike: { onLike(answer) },
                                onComments: { onComments(answer) },
                                loadMedia: loadMedia
                            )
                            .padding(.top, index == 0 ? 12 : 0)
                        }
                    }

                    if tab == .profile {
                        if hasMoreHistory, let onLoadMoreHistory {
                            TextRaisedButton(
                                title: isLoadingMoreHistory ? "読み込み中…" : "さらに古い回答を読む",
                                icon: "arrow.down.circle",
                                height: 60,
                                fontSize: 21,
                                action: onLoadMoreHistory
                            )
                            .padding(.horizontal, 34)
                            .disabled(isLoadingMoreHistory)
                            .accessibilityIdentifier("history-load-more-button")
                        } else if !visibleAnswers.isEmpty {
                            Text("すべての回答を表示しました")
                                .font(TsutsuuraTheme.displayFont(18))
                                .foregroundStyle(.white)
                                .accessibilityIdentifier("history-end-label")
                        }
                    } else if hasMoreFamilyAnswers,
                              let onLoadMoreFamilyAnswers {
                        TextRaisedButton(
                            title: isLoadingMoreFamilyAnswers
                                ? "読み込み中…"
                                : "さらに家族の回答を読む",
                            icon: "arrow.down.circle",
                            height: 60,
                            fontSize: 21,
                            action: onLoadMoreFamilyAnswers
                        )
                        .padding(.horizontal, 34)
                        .disabled(isLoadingMoreFamilyAnswers)
                        .accessibilityIdentifier("family-feed-load-more-button")
                    }

                    Spacer(minLength: 24)
                }
                .padding(.top, 0)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.always, axes: .vertical)
            .accessibilityIdentifier(tab == .family ? "home-family-timeline" : "home-profile-timeline")
            .modifier(HomeBannerPullToReveal(
                enabled: selectedTab == tab && canRevealUpcomingQuestion,
                contextID: "\(bannerAccountKey):\(questionBannerKey)",
                onReveal: revealUpcomingQuestion
            ))
    }

    private func searchNow() {
        dismissHistorySearchKeyboard()
        searchTask?.cancel()
        onHistorySearch?(historySearchText)
    }

    private func dismissHistorySearchKeyboard() {
        isHistorySearchFocused = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        #endif
    }
}

private struct NewQuestionHero: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let question: Question
    let tint: Color
    let onQuestion: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        let schedule = QuestionSchedulePresentation(question: question)
        ZStack {
            DottedBackdrop(
                background: TsutsuuraTheme.ink,
                dot: TsutsuuraTheme.dot
            )
            .overlay(tint.opacity(0.5))

            VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 8 : 16) {
                Text(schedule.title)
                    .font(TsutsuuraTheme.displayFont(dynamicTypeSize.isAccessibilitySize ? 22 : 36))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)

                if question.isAvailable == false {
                    if let release = schedule.releaseInScheduleTimeZone {
                        Text(release)
                            .font(TsutsuuraTheme.bodyFont(24))
                            .foregroundStyle(.white)
                    }
                    if let localRelease = schedule.releaseInLocalTimeZone {
                        Text(localRelease)
                            .font(TsutsuuraTheme.bodyFont(20))
                            .foregroundStyle(.white)
                    }
                    Text("先に、家族の回答を読んでみましょう。")
                        .font(TsutsuuraTheme.bodyFont(18))
                        .foregroundStyle(.white)
                } else {
                if schedule.title != "本日の質問!" {
                    Text(schedule.questionDateLabel)
                        .font(TsutsuuraTheme.bodyFont(18))
                        .foregroundStyle(.white)
                }
                TextRaisedButton(
                    title: "回答する",
                    fill: tint,
                    shadow: tint == TsutsuuraTheme.orange
                        ? TsutsuuraTheme.orangeDark
                        : TsutsuuraTheme.cyanDark,
                    height: 62,
                    fontSize: dynamicTypeSize.isAccessibilitySize ? 22 : 30,
                    haptic: .success,
                    action: onQuestion
                )
                .frame(minWidth: 132, maxWidth: 240)
                }
            }
            .padding(.horizontal, question.isAvailable == false ? 48 : 24)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 20)
        }
        .overlay(alignment: .topTrailing) {
            if question.isAvailable == false {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("次の質問のお知らせを閉じる")
                .accessibilityIdentifier("dismiss-upcoming-question")
            }
        }
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 100 : 150)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 16)
                .onEnded { value in
                    let upwardDistance = -value.translation.height
                    guard question.isAvailable == false,
                          upwardDistance >= 48,
                          upwardDistance > abs(value.translation.width) else { return }
                    onDismiss()
                },
            // Consume drags even after publication so a swipe beginning on
            // the answer button cannot finish as a button press. The handler
            // above still permits dismissal only for an upcoming question.
            including: .all
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-question-banner")
    }
}

private struct FamilyProgress: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let progress: FamilyAnswerProgress
    let topPadding: CGFloat
    @State private var showsMembers = false

    var body: some View {
        VStack(spacing: 0) {
            let batteryLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 16))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 5))
            batteryLayout {
                FamilyBatteryGauge(progress: progress)
                    .frame(height: 112)

                if !progress.members.isEmpty {
                    RaisedButton(
                        fill: TsutsuuraTheme.cyan,
                        shadow: TsutsuuraTheme.cyanDark,
                        height: dynamicTypeSize.isAccessibilitySize ? 64 : 107,
                        isSelected: showsMembers,
                        action: {
                            withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
                                showsMembers.toggle()
                            }
                        }
                    ) {
                        if dynamicTypeSize.isAccessibilitySize {
                            Text("確認")
                                .font(TsutsuuraTheme.displayFont(36))
                                .padding(12)
                        } else {
                            VStack(spacing: 12) {
                                Text("確").frame(height: 42)
                                Text("認").frame(height: 42)
                            }
                            .font(TsutsuuraTheme.displayFont(36))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 78)
                    .accessibilityLabel(showsMembers ? "家族の回答状況を閉じる" : "家族の回答状況を確認")
                    .accessibilityValue(showsMembers ? "開いています" : "閉じています")
                    .accessibilityIdentifier("family-progress-details-button")
                }
            }
            .padding(.top, 8)

            if progress.total == 0 {
                Text("家族の情報を読み込むと、回答状況が表示されます。")
                    .font(TsutsuuraTheme.bodyFont(20))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(24)
            }

            if showsMembers && !progress.members.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(progress.members.enumerated()), id: \.element.id) { index, member in
                        let hasAnswered = progress.answeredUserIDs.contains(member.id)
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(
                                systemName: hasAnswered
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(
                                hasAnswered
                                    ? TsutsuuraTheme.cyanDark
                                    : TsutsuuraTheme.skyInk
                            )
                            .accessibilityHidden(true)

                            let memberLayout = dynamicTypeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                : AnyLayout(HStackLayout(spacing: 8))
                            memberLayout {
                                Text(member.displayName)
                                    .font(TsutsuuraTheme.displayFont(23))
                                    .foregroundStyle(TsutsuuraTheme.ink)
                                    .fixedSize(horizontal: false, vertical: true)

                                if !dynamicTypeSize.isAccessibilitySize {
                                    Spacer(minLength: 8)
                                }

                                Text(hasAnswered ? "回答済み" : "未回答")
                                    .font(TsutsuuraTheme.displayFont(20))
                                    .foregroundStyle(TsutsuuraTheme.skyInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "\(member.displayName)：\(hasAnswered ? "回答済み" : "未回答")"
                        )

                        if index < progress.members.count - 1 {
                            Divider()
                                .overlay(TsutsuuraTheme.skyInk.opacity(0.18))
                                .padding(.horizontal, 16)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .background(TsutsuuraTheme.sky)
                .padding(.top, 10)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.leading, 33)
        .padding(.trailing, 34)
        .padding(.top, topPadding)
    }
}

private struct FamilyBatteryGauge: View {
    let progress: FamilyAnswerProgress

    var body: some View {
        ZStack {
            HStack(spacing: progress.total > 12 ? 2 : 5) {
                ForEach(0..<progress.total, id: \.self) { index in
                    let answered = index < progress.members.count
                        ? progress.answeredUserIDs.contains(progress.members[index].id)
                        : index - progress.members.count < progress.answered
                            - progress.members.filter { progress.answeredUserIDs.contains($0.id) }.count
                    Rectangle()
                        .fill(answered ? TsutsuuraTheme.cyan : TsutsuuraTheme.batteryEmpty)
                }
            }
            .padding(5)
            UnevenPaperHighlight().fill(.white.opacity(0.2))
            Rectangle().strokeBorder(TsutsuuraTheme.cyanDark, lineWidth: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日の家族の回答")
        .accessibilityValue(progress.total > 0
            ? "\(progress.total)人中\(progress.answered)人が回答済み"
            : "家族の情報を読み込み中")
        .accessibilityIdentifier("family-answer-battery")
    }
}

private struct EmptyFeedState: View {
    let isFamily: Bool
    var hasActiveFilters = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: isFamily ? "person.3.fill" : "text.book.closed.fill")
                .font(.system(size: 46, weight: .bold))
                .accessibilityHidden(true)
            Text(hasActiveFilters
                ? "条件に合う回答がありません"
                : (isFamily ? "家族の回答はまだありません" : "過去の回答はまだありません"))
                .font(TsutsuuraTheme.displayFont(27))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if hasActiveFilters {
                Text("言葉を短くするか、「すべての回答に戻る」を押してください")
                    .font(TsutsuuraTheme.bodyFont(size: 19))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white.opacity(0.75))
        .frame(maxWidth: .infinity)
    }
}

enum AnswerCardActionMode: Equatable {
    case none
    case family
    case profile
}

struct AnswerCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let answer: Answer
    let actionMode: AnswerCardActionMode
    let canLike: Bool
    let onLike: () -> Void
    let onComments: () -> Void
    let loadMedia: AnswerMediaLoader
    var onEdit: (() -> Void)? = nil

    private var photoCount: Int {
        answer.media.lazy.filter { $0.kind == .photo }.count
    }

    private var hasAudio: Bool {
        answer.media.contains { $0.kind == .audio }
    }

    private var minimumPanelHeight: CGFloat {
        let baseHeight: CGFloat
        if actionMode == .none {
            baseHeight = 254
        } else if canLike {
            baseHeight = 290
        } else {
            // Own answers do not render the like row, so they need less
            // reserved whitespace. Keeping this card compact also prevents
            // its comment action from sitting beneath the bottom navigation
            // on short iPhones.
            baseHeight = 264
        }
        let photoHeight: CGFloat = photoCount == 0 ? 0 : 207
        let audioHeight: CGFloat = hasAudio ? 63 : 0
        return baseHeight + photoHeight + audioHeight
    }

    var body: some View {
        VStack(spacing: 10) {
            let authorLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 12))
            authorLayout {
                PersonBadge(
                    name: answer.author.displayName,
                    tint: TsutsuuraTheme.cyanDark,
                    mark: answer.author.avatarMark
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(Self.dateFormatter.string(from: answer.createdAt))
                    .font(TsutsuuraTheme.displayFont(24))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            }

            PaperPanel {
                VStack(
                    alignment: .leading,
                    spacing: actionMode == .none ? 28 : 13
                ) {
                    if let prompt = answer.questionPrompt {
                        Text("Q. \(prompt)")
                            .font(TsutsuuraTheme.displayFont(27))
                            .foregroundStyle(TsutsuuraTheme.skyMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !answer.body.isEmpty {
                        Text(answer.body)
                            .font(TsutsuuraTheme.displayFont(30))
                            .foregroundStyle(TsutsuuraTheme.ink)
                            .lineSpacing(actionMode == .none ? 20 : 9)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                    }

                    if !answer.media.isEmpty {
                        AnswerMediaGallery(
                            media: answer.media,
                            loadMedia: loadMedia
                        )
                    }

                    Spacer(minLength: 6)

                    if answer.likeCount > 0, actionMode != .none {
                        Text("いいね \(answer.likeCount)")
                            .font(TsutsuuraTheme.displayFont(24))
                        .foregroundStyle(TsutsuuraTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("いいね\(answer.likeCount)件")
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, actionMode == .none ? 12 : 28)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
            }
            .frame(minHeight: minimumPanelHeight)

            if actionMode == .family && canLike {
                let actionLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 14))
                    : AnyLayout(HStackLayout(spacing: 12))
                actionLayout {
                    TextRaisedButton(
                        title: answer.isLikedByMe ? "いいね済" : "いいね",
                        fill: TsutsuuraTheme.cyan,
                        shadow: TsutsuuraTheme.cyanDark,
                        height: 62,
                        fontSize: 23,
                        isSelected: answer.isLikedByMe,
                        action: onLike
                    )
                    .accessibilityValue(answer.isLikedByMe ? "選択中" : "")
                    .accessibilityHint(answer.isLikedByMe ? "もう一度押すといいねを取り消します" : "この回答にいいねを送ります")

                    TextRaisedButton(
                        title: "コメント",
                        icon: "text.bubble.fill",
                        height: 62,
                        fontSize: 23,
                        action: onComments
                    )
                    .accessibilityIdentifier("answer-comments-\(answer.id)")
                }
            } else if actionMode == .family || actionMode == .profile {
                TextRaisedButton(
                    title: "コメント",
                    icon: "text.bubble.fill",
                    height: 62,
                    fontSize: 27,
                    action: onComments
                )
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 220)
                .accessibilityIdentifier("answer-comments-\(answer.id)")
            }

        }
        .padding(.horizontal, 34)
        .accessibilityElement(children: .contain)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "MM/dd (E)"
        return formatter
    }()
}

private struct BottomNavigation: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selectedTab: HomeTab

    var body: some View {
        HStack(spacing: 10) {
            tabButton(
                title: "家族",
                icon: "figure.2.and.child.holdinghands",
                tab: .family
            )
            tabButton(
                title: "あなた",
                icon: "person.crop.circle.fill",
                tab: .profile
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(TsutsuuraTheme.ink)
    }

    private func tabButton(
        title: String,
        icon: String,
        tab: HomeTab
    ) -> some View {
        Button { selectedTab = tab } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                Text(title)
                if selectedTab == tab {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .font(TsutsuuraTheme.displayFont(dynamicTypeSize.isAccessibilitySize ? 23 : 24))
            .foregroundStyle(selectedTab == tab ? TsutsuuraTheme.cyanDark : .white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.vertical, 2)
            .background(selectedTab == tab ? TsutsuuraTheme.sky : TsutsuuraTheme.cyanDark)
            .overlay(Rectangle().strokeBorder(selectedTab == tab ? .white : TsutsuuraTheme.cyan, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(tab == .family ? "home-tab-family" : "home-tab-profile")
        .accessibilityValue(selectedTab == tab ? "選択中" : "")
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }
}

struct QuestionScreen: View {
    private static let keyboardAnchorID = "question-answer-keyboard-anchor"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let question: Question
    @Binding var answerText: String
    let voiceRecording: AnswerMediaUpload?
    let photos: [AnswerMediaUpload]
    let isSubmitting: Bool
    let onBack: () -> Void
    let onVoice: () -> Void
    let onAddPhotos: ([AnswerMediaUpload]) -> Bool
    let onRemoveVoice: () -> Void
    let onRemovePhoto: (UUID) -> Void
    let onMediaError: (String) -> Void
    let onSubmit: () -> Void
    var hasNewQuestion = false
    var onNewQuestion: (() -> Void)? = nil

    @FocusState private var isAnswerFocused: Bool
    @State private var confirmsSubmission = false

    private var isAnswerEmpty: Bool {
        answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && voiceRecording == nil
            && photos.isEmpty
    }

    private var isSubmitDisabled: Bool {
        isAnswerEmpty || isSubmitting || !question.canAnswer || hasNewQuestion
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            LifecyclePage(title: "本日の質問", onBack: goBack) {
                if hasNewQuestion {
                    Text("新しい質問が届きました。この下書きは前の質問のものです。")
                        .font(TsutsuuraTheme.bodyFont(21))
                        .foregroundStyle(.white)
                    TextRaisedButton(title: "新しい質問を確認", fontSize: 22) {
                        onNewQuestion?()
                    }
                }
                PaperPanel {
                    Text(question.prompt)
                        .font(TsutsuuraTheme.displayFont(32))
                        .foregroundStyle(TsutsuuraTheme.ink)
                        .multilineTextAlignment(.center)
                        .lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(24)
                        .frame(maxWidth: .infinity)
                }

                PaperPanel {
                    ZStack(alignment: .topLeading) {
                        if answerText.isEmpty {
                            Text("回答を入力…")
                                .font(TsutsuuraTheme.bodyFont(size: 23))
                                .foregroundStyle(TsutsuuraTheme.skyMuted)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 17)
                                .accessibilityHidden(true)
                        }
                        TextEditor(text: $answerText)
                            .focused($isAnswerFocused)
                            .font(TsutsuuraTheme.bodyFont(size: 23))
                            .foregroundStyle(TsutsuuraTheme.ink)
                            .scrollContentBackground(.hidden)
                            .scrollDismissesKeyboard(.interactively)
                            .padding(10)
                            .background(.clear)
                            .frame(minHeight: 210)
                            .accessibilityLabel("回答")
                            .accessibilityHint("本日の質問への回答を入力します")
                            .accessibilityIdentifier("answer-input")
                            .onChange(of: answerText) { _, value in
                                if UnicodeTextValidation.characterCount(value)
                                    > AnswerDraft.maximumBodyCharacterCount {
                                    answerText = UnicodeTextValidation.clamped(
                                        value,
                                        maximumLength: AnswerDraft.maximumBodyCharacterCount
                                    )
                                }
                            }
                    }
                    .padding(6)
                }

                Text("\(UnicodeTextValidation.characterCount(answerText)) / \(AnswerDraft.maximumBodyCharacterCount)文字")
                    .font(TsutsuuraTheme.bodyFont(size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .id(Self.keyboardAnchorID)

                if voiceRecording != nil || !photos.isEmpty {
                    AnswerDraftMediaStrip(
                        voiceRecording: voiceRecording,
                        photos: photos,
                        onRemoveVoice: onRemoveVoice,
                        onRemovePhoto: onRemovePhoto
                    )
                    .frame(minHeight: 62)
                    .transition(.scale.combined(with: .opacity))
                }

                HStack(spacing: 12) {
                    TextRaisedButton(
                        title: voiceRecording == nil ? "声で回答" : "声を変更",
                        icon: "waveform",
                        fill: voiceRecording == nil
                            ? TsutsuuraTheme.cyan
                            : TsutsuuraTheme.green,
                        shadow: voiceRecording == nil
                            ? TsutsuuraTheme.cyanDark
                            : TsutsuuraTheme.greenDark,
                        height: 60,
                        fontSize: 19,
                        action: presentVoiceAnswer
                    )
                    .accessibilityLabel("声で回答")

                    #if canImport(PhotosUI)
                    AnswerPhotoPickerButton(
                        currentPhotoCount: photos.count,
                        onAddPhotos: onAddPhotos,
                        onError: onMediaError
                    )
                    #endif
                }

                Text("送った回答は変更・削除できません。送る前に、内容を確かめましょう。")
                    .font(TsutsuuraTheme.bodyFont(19))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                TextRaisedButton(
                    title: isSubmitting ? "送信中…" : "この回答を送る",
                    icon: "paperplane.fill",
                    height: 68,
                    fontSize: 24,
                    haptic: .success,
                    action: submitAnswer
                )
                .disabled(isSubmitDisabled)
                .accessibilityIdentifier("submit-answer-button")

                if isAnswerFocused {
                    Color.clear
                        .frame(height: 280)
                        .accessibilityHidden(true)
                }
            }
            .animation(
                TsutsuuraMotion.respectingReduceMotion(
                    reduceMotion,
                    TsutsuuraMotion.quickSpring
                ),
                value: isAnswerFocused
            )
            .animation(
                TsutsuuraMotion.respectingReduceMotion(
                    reduceMotion,
                    TsutsuuraMotion.spring
                ),
                value: photos.count
            )
            .animation(
                TsutsuuraMotion.respectingReduceMotion(
                    reduceMotion,
                    TsutsuuraMotion.spring
                ),
                value: voiceRecording?.id
            )
            .onChange(of: isAnswerFocused) { _, focused in
                guard focused else { return }
                revealAnswerEditor(using: scrollProxy)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIResponder.keyboardDidChangeFrameNotification
                )
            ) { _ in
                guard isAnswerFocused else { return }
                revealAnswerEditor(using: scrollProxy)
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Button("閉じる") {
                        isAnswerFocused = false
                    }
                    .accessibilityIdentifier("dismiss-answer-keyboard")

                    Spacer()

                    Button("回答", action: submitAnswer)
                        .disabled(isSubmitDisabled)
                        .accessibilityIdentifier("submit-answer-from-keyboard")
                }
            }
        }
        .alert("この内容で家族に送りますか？", isPresented: $confirmsSubmission) {
            Button("家族に送る") { onSubmit() }
            Button("戻って確認", role: .cancel) {}
        } message: {
            Text("送った後は変更・削除できません。\n\n\(answerText)")
        }
    }

    private func revealAnswerEditor(using scrollProxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            guard isAnswerFocused else { return }
            withAnimation(
                TsutsuuraMotion.respectingReduceMotion(
                    reduceMotion,
                    TsutsuuraMotion.quickSpring
                )
            ) {
                scrollProxy.scrollTo(Self.keyboardAnchorID, anchor: .bottom)
            }
        }
    }

    private func goBack() {
        isAnswerFocused = false
        onBack()
    }

    private func presentVoiceAnswer() {
        isAnswerFocused = false
        onVoice()
    }

    private func submitAnswer() {
        guard !isSubmitDisabled else { return }
        isAnswerFocused = false
        confirmsSubmission = true
    }
}

struct VoiceAnswerScreen: View {
    let prompt: String
    @Binding var transcript: String
    let level: CGFloat
    let isRecording: Bool
    let hasRecording: Bool
    let errorMessage: String?
    let captureState: SpeechCaptureState
    let onStartRecording: () async -> Void
    let onStopRecording: () -> Void
    let onCancel: () -> Void
    let onUseTranscript: () -> Void
    let onOpenSettings: () -> Void
    let onUseTextAnswer: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var countdown = 3
    @State private var countdownFinished = false

    private var hasCaptureError: Bool {
        errorMessage != nil && !isRecording
    }

    private var recordingStatus: String {
        if !transcript.isEmpty { return transcript }
        if hasRecording && !isRecording {
            return hasCaptureError
                ? "録音が中断されました。録音済みの内容を使えます。"
                : "録音できました。「この回答を使う」で進めます。"
        }
        if hasCaptureError { return "録音は始まっていません" }
        if !countdownFinished { return "まもなく録音を始めます…" }
        return isRecording ? "声を聞いています…" : "録音ボタンを押して話してください"
    }

    var body: some View {
        ZStack {
            DottedBackdrop()

            ScrollView(showsIndicators: false) {
            VStack(spacing: 27) {
                HStack {
                    Button {
                        HapticPlayer.play(.selection)
                        onCancel()
                    } label: {
                        Label("戻る", systemImage: "chevron.left")
                            .font(TsutsuuraTheme.displayFont(27))
                            .foregroundStyle(.white)
                            .frame(minWidth: 64, minHeight: 52, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                Text(prompt)
                    .font(TsutsuuraTheme.displayFont(27))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 94)

                ZStack {
                    Circle()
                        .fill(TsutsuuraTheme.cyan.opacity(0.18))
                        .frame(
                            width: hasCaptureError ? 170 : 260,
                            height: hasCaptureError ? 170 : 260
                        )
                        .scaleEffect(isRecording && !reduceMotion ? 1.08 : 0.92)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                            value: isRecording
                        )

                    if hasCaptureError {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 64, weight: .bold))
                            .foregroundStyle(.white)
                            .accessibilityHidden(true)
                    } else if countdownFinished {
                        AnimatedWaveform(level: level, isActive: isRecording)
                            .frame(width: 250, height: 150)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("\(countdown)")
                            .font(TsutsuuraTheme.displayFont(112))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .id(countdown)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: hasCaptureError ? 180 : 280)

                PaperPanel {
                    ScrollView {
                        Text(recordingStatus)
                            .font(TsutsuuraTheme.font(28))
                            .foregroundStyle(
                                transcript.isEmpty || hasCaptureError
                                    ? TsutsuuraTheme.skyMuted
                                    : TsutsuuraTheme.ink
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(22)
                    }
                }
                .frame(height: 164)

                if let errorMessage {
                    Text(errorMessage)
                        .font(TsutsuuraTheme.font(20))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                if hasCaptureError {
                    VStack(spacing: 12) {
                        if hasRecording {
                            TextRaisedButton(
                                title: "録音内容を使う",
                                icon: "checkmark",
                                fill: TsutsuuraTheme.green,
                                shadow: TsutsuuraTheme.greenDark,
                                height: 64,
                                fontSize: 24,
                                haptic: .success,
                                action: onUseTranscript
                            )
                            .accessibilityIdentifier("use-interrupted-recording")
                        }
                        if captureState == .permissionDenied {
                            TextRaisedButton(
                                title: "設定を開く",
                                icon: "gearshape.fill",
                                fill: TsutsuuraTheme.orange,
                                shadow: TsutsuuraTheme.orangeDark,
                                height: 64,
                                fontSize: 24,
                                action: onOpenSettings
                            )
                            .accessibilityIdentifier("open-voice-permission-settings")
                        } else {
                            TextRaisedButton(
                                title: "もう一度試す",
                                icon: "arrow.clockwise",
                                height: 64,
                                fontSize: 24
                            ) {
                                Task {
                                    await onStartRecording()
                                }
                            }
                            .accessibilityIdentifier("retry-voice-recording")
                        }

                        TextRaisedButton(
                            title: "テキストで回答する",
                            icon: "keyboard",
                            fill: TsutsuuraTheme.cyan,
                            shadow: TsutsuuraTheme.cyanDark,
                            height: 64,
                            fontSize: 24,
                            action: onUseTextAnswer
                        )
                        .accessibilityIdentifier("use-text-answer-instead")
                    }
                } else {
                    let recordingLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: 14))
                        : AnyLayout(HStackLayout(spacing: 12))
                    recordingLayout {
                        TextRaisedButton(
                            title: isRecording ? "停止" : "録音",
                            icon: isRecording ? "stop.fill" : "mic.fill",
                            fill: isRecording ? TsutsuuraTheme.coral : TsutsuuraTheme.cyan,
                            shadow: isRecording
                                ? Color(hex: 0x713038)
                                : TsutsuuraTheme.cyanDark,
                            height: 64,
                            fontSize: 26
                        ) {
                            if isRecording {
                                onStopRecording()
                            } else {
                                Task {
                                    await onStartRecording()
                                }
                            }
                        }
                        .disabled(!countdownFinished)

                        TextRaisedButton(
                            title: "この回答を使う",
                            icon: "checkmark",
                            height: 64,
                            fontSize: 26,
                            haptic: .success,
                            action: onUseTranscript
                        )
                        .accessibilityIdentifier("voice-use-answer-button")
                        .disabled(transcript.isEmpty && !isRecording && !hasRecording)
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 54)
            .padding(.bottom, 44)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard !countdownFinished else { return }
            for number in stride(from: 3, through: 1, by: -1) {
                countdown = number
                HapticPlayer.play(.selection)
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            withAnimation(
                TsutsuuraMotion.respectingReduceMotion(
                    reduceMotion,
                    TsutsuuraMotion.emphasizedSpring
                )
            ) {
                countdownFinished = true
            }
            await onStartRecording()
        }
    }
}

private struct AnimatedWaveform: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let level: CGFloat
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive || reduceMotion)) {
            timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let barCount = 23
                let barWidth: CGFloat = 6
                let gap = (size.width - CGFloat(barCount) * barWidth)
                    / CGFloat(barCount - 1)

                for index in 0..<barCount {
                    let phase = Double(index) * 0.62 + time * 7
                    let pulse = reduceMotion ? 0.38 : (sin(phase) + 1) / 2
                    let envelope = sin(
                        Double(index + 1) / Double(barCount + 1) * .pi
                    )
                    let liveLevel = max(0.16, min(1, level))
                    let height = max(
                        12,
                        size.height * CGFloat(pulse * envelope) * liveLevel
                    )
                    let rect = CGRect(
                        x: CGFloat(index) * (barWidth + gap),
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(TsutsuuraTheme.cyan)
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct CommentsScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let answer: Answer
    let comments: [Comment]
    let currentUserID: String
    let focusedCommentID: String?
    let hasMoreComments: Bool
    @Binding var draft: String
    let isLoading: Bool
    let onBack: () -> Void
    let onSend: () -> Void
    let onLoadMore: () -> Void
    let loadMedia: AnswerMediaLoader
    var onReply: ((Comment) -> Void)? = nil
    var onReport: ((Comment) -> Void)? = nil

    @FocusState private var isCommentFocused: Bool
    @State private var pendingReport: Comment?
    @State private var shouldRevealNewestComment = false
    @State private var replyingTo: Comment?

    private var isSendDisabled: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || isLoading
    }

    var body: some View {
        ZStack(alignment: .top) {
            DottedBackdrop()

            VStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) {
                        commentsBackButton
                        Spacer(minLength: 0)
                        commentsTitle
                            .fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        commentsBackButton
                        commentsTitle
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 64)
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 12)

                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 17) {
                            AnswerCard(
                                answer: answer,
                                actionMode: .none,
                                canLike: false,
                                onLike: {},
                                onComments: {},
                                loadMedia: loadMedia
                            )

                            ForEach(comments) { comment in
                                VStack(alignment: .leading, spacing: 9) {
                                    commentHeader(for: comment)

                                    PaperPanel {
                                        VStack(alignment: .leading, spacing: 6) {
                                            if comment.parentCommentID != nil {
                                                Label("返信", systemImage: "arrowshape.turn.up.left.fill")
                                                    .font(TsutsuuraTheme.displayFont(18))
                                                    .foregroundStyle(TsutsuuraTheme.skyInk)
                                            }
                                            Text(comment.body)
                                                .font(TsutsuuraTheme.displayFont(24))
                                                .foregroundStyle(TsutsuuraTheme.ink)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            if let updatedAt = comment.updatedAt,
                                               updatedAt.timeIntervalSince(comment.createdAt) > 1 {
                                                Text("編集済み")
                                                    .font(TsutsuuraTheme.displayFont(18))
                                                    .foregroundStyle(TsutsuuraTheme.skyInk)
                                            }
                                        }
                                        .padding(16)
                                    }
                                    .frame(minHeight: 80)
                                    .overlay {
                                        if comment.id == focusedCommentID {
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(
                                                    TsutsuuraTheme.orange,
                                                    lineWidth: 5
                                                )
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    .accessibilityIdentifier(
                                        comment.id == focusedCommentID
                                            ? "focused-comment-\(comment.id)"
                                            : "comment-\(comment.id)"
                                    )

                                    if comment.author.id != currentUserID {
                                        HStack(spacing: 16) {
                                            if onReply != nil {
                                                Button("返信") {
                                                    replyingTo = comment
                                                    isCommentFocused = true
                                                }
                                            }
                                            if onReport != nil {
                                                Button("報告") {
                                                    pendingReport = comment
                                                }
                                            }
                                        }
                                        .font(TsutsuuraTheme.displayFont(20))
                                        .foregroundStyle(.white)
                                        .frame(minHeight: 44)
                                    }
                                }
                                .padding(.horizontal, 34)
                                .accessibilityElement(children: .contain)
                                .id(comment.id)
                            }

                            if hasMoreComments {
                                Button {
                                    onLoadMore()
                                } label: {
                                    Label(
                                        isLoading
                                            ? "読み込んでいます…"
                                            : "以前のコメントを読み込む",
                                        systemImage: "arrow.down.circle"
                                    )
                                    .font(TsutsuuraTheme.displayFont(21))
                                    .foregroundStyle(.white)
                                    .frame(minHeight: 52)
                                }
                                .buttonStyle(.plain)
                                .disabled(isLoading)
                                .accessibilityIdentifier("comments-load-more-button")
                            }

                            if comments.isEmpty && !isLoading {
                                Text("最初のコメントを書こう")
                                    .font(TsutsuuraTheme.displayFont(24))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .padding(.top, 30)
                            }

                            // Leave enough scroll range for the final comment's
                            // reply/report actions to clear the persistent composer.
                            Color.clear
                                .frame(height: 96)
                                .id(Self.commentScrollEndID)
                                .accessibilityHidden(true)
                        }
                        .padding(.top, 2)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear {
                        revealFocusedComment(using: scrollProxy)
                    }
                    .onChange(of: focusedCommentID) { _, _ in
                        revealFocusedComment(using: scrollProxy)
                    }
                    .onChange(of: comments.count) { oldCount, newCount in
                        if focusedCommentID != nil {
                            revealFocusedComment(using: scrollProxy)
                        }
                        guard shouldRevealNewestComment,
                              newCount > oldCount else {
                            return
                        }
                        shouldRevealNewestComment = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation(
                                TsutsuuraMotion.respectingReduceMotion(
                                    reduceMotion,
                                    TsutsuuraMotion.quickSpring
                                )
                            ) {
                                scrollProxy.scrollTo(
                                    Self.commentScrollEndID,
                                    anchor: .bottom
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                commentComposer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(
            "このコメントを報告しますか？",
            isPresented: Binding(
                get: { pendingReport != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingReport = nil
                    }
                }
            ),
            presenting: pendingReport
        ) { comment in
            Button("不適切な内容として報告") {
                pendingReport = nil
                onReport?(comment)
            }
            Button("キャンセル", role: .cancel) {
                pendingReport = nil
            }
        } message: { _ in
            Text("家族へ通知せず、サービスの安全確認に送ります。緊急時は身近な方や公的窓口にも相談してください。")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("閉じる") {
                    isCommentFocused = false
                }
                .accessibilityIdentifier("dismiss-comment-keyboard")
            }
        }
    }

    private func revealFocusedComment(using scrollProxy: ScrollViewProxy) {
        guard let focusedCommentID,
              comments.contains(where: { $0.id == focusedCommentID }) else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(
                TsutsuuraMotion.respectingReduceMotion(
                    reduceMotion,
                    TsutsuuraMotion.quickSpring
                )
            ) {
                scrollProxy.scrollTo(focusedCommentID, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func commentHeader(for comment: Comment) -> some View {
        let commentHeaderLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        commentHeaderLayout {
            PersonBadge(name: comment.author.displayName, mark: comment.author.avatarMark)

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }

            Text(Self.commentDateFormatter.string(from: comment.createdAt))
                .font(TsutsuuraTheme.displayFont(18))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var commentsTitle: some View {
        Text("コメント")
            .font(TsutsuuraTheme.displayFont(32))
            .foregroundStyle(.white)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("comments-screen-title")
    }

    private var commentsBackButton: some View {
        Button {
            HapticPlayer.play(.selection)
            goBack()
        } label: {
            Label("戻る", systemImage: "chevron.left")
                .font(TsutsuuraTheme.displayFont(24))
                .foregroundStyle(.white)
                .fixedSize()
                .frame(minWidth: 64, minHeight: 54, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var commentComposer: some View {
        VStack(spacing: 0) {
            if let replyingTo {
                HStack {
                    Text("\(replyingTo.author.displayName)へ返信")
                        .font(TsutsuuraTheme.displayFont(18))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("返信をやめる") { self.replyingTo = nil }
                        .font(TsutsuuraTheme.displayFont(18))
                        .foregroundStyle(.white)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 24)
                .background(TsutsuuraTheme.ink.opacity(0.94))
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .trailing, spacing: 4) {
                    TextField(
                        "",
                        text: $draft,
                        prompt: Text("コメントを入力")
                            .foregroundStyle(TsutsuuraTheme.skyMuted)
                    )
                    .focused($isCommentFocused)
                    .font(TsutsuuraTheme.font(23))
                    .foregroundStyle(TsutsuuraTheme.ink)
                    .submitLabel(.send)
                    .onSubmit(sendComment)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 58)
                    .background(TsutsuuraTheme.sky)
                    .overlay(Rectangle().stroke(TsutsuuraTheme.skyInk, lineWidth: 3))
                    .accessibilityLabel("コメント")
                    .accessibilityIdentifier("comment-input")
                    .onChange(of: draft) { _, value in
                        if UnicodeTextValidation.characterCount(value)
                            > Comment.maximumBodyCharacterCount {
                            draft = UnicodeTextValidation.clamped(
                                value,
                                maximumLength: Comment.maximumBodyCharacterCount
                            )
                        }
                    }

                }

                TextRaisedButton(
                    title: "送信",
                    height: 58,
                    fontSize: 23,
                    haptic: .success,
                    action: sendComment
                )
                .frame(width: 90)
                .disabled(isSendDisabled)
                .accessibilityIdentifier("comment-send-button")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(TsutsuuraTheme.ink.opacity(0.94))
        }
    }

    private func sendComment() {
        guard !isSendDisabled else { return }
        shouldRevealNewestComment = true
        isCommentFocused = false
        if let replyingTo {
            onReply?(replyingTo)
            self.replyingTo = nil
        } else {
            onSend()
        }
    }

    private func goBack() {
        isCommentFocused = false
        onBack()
    }

    private static let commentDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d H:mm"
        return formatter
    }()

    private static let commentScrollEndID = "comments-scroll-end"
}

struct SettingsScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let profile: UserProfile
    @Binding var displayName: String
    let onBack: () -> Void
    let onSaveName: () async -> Bool
    let onFamilySettings: () -> Void
    let onRefresh: () async -> Bool
    let onSignOut: () -> Void
    var onNotificationSettings: (() -> Void)? = nil
    var onAccountPrivacy: (() -> Void)? = nil
    var onHelp: (() -> Void)? = nil
    var onPersonalMark: (() -> Void)? = nil

    @FocusState private var isDisplayNameFocused: Bool
    @State private var saveFeedback: String?
    @State private var refreshFeedback: String?
    @State private var isSignOutConfirmationPresented = false
    @State private var isSavingName = false
    @State private var isRefreshingData = false

    private var normalizedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveDisplayName: Bool {
        !normalizedDisplayName.isEmpty
            && normalizedDisplayName != profile.displayName
            && !isSavingName
    }

    private var signOutWarning: String {
        if profile.managed == true {
            return "ログアウト後は、保存した復旧コードで戻れます。コードがない場合は、ご家族から新しい設定番号を送ってもらう必要があります。"
        }
        if profile.hasEmail == true {
            return "ログアウト後は、登録したメールアドレスで再度ログインできます。"
        }
        return "メールアドレスが登録されていません。保存した復旧コードがなければ元のアカウントへ戻れません。先に「機種変更・データの保存」で準備してください。"
    }

    var body: some View {
        ZStack(alignment: .top) {
            DottedBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                settingsHeader

                PaperPanel {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("家族に見える名前")
                            .font(TsutsuuraTheme.bodyFont(size: 22, weight: .semibold))
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("名前", text: $displayName)
                                .focused($isDisplayNameFocused)
                                .font(TsutsuuraTheme.font(30))
                                .textFieldStyle(.plain)
                                .submitLabel(.done)
                                .onSubmit(saveDisplayName)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(minHeight: 52)
                                .background(
                                    .white.opacity(
                                        isDisplayNameFocused ? 0.68 : 0.50
                                    )
                                )
                                .overlay(
                                    Rectangle()
                                        .stroke(
                                            TsutsuuraTheme.skyInk,
                                            lineWidth: isDisplayNameFocused ? 3 : 2
                                        )
                                )
                                .accessibilityLabel("表示名")
                                .accessibilityIdentifier("settings-name-input")
                                .onChange(of: displayName) { _, newValue in
                                    if NameValidation.characterCount(newValue)
                                        > NameValidation.maximumLength {
                                        displayName = NameValidation.clamped(newValue)
                                    }
                                    saveFeedback = nil
                                }

                            if isDisplayNameFocused {
                            Text("\(NameValidation.characterCount(displayName)) / \(NameValidation.maximumLength)文字")
                                .font(TsutsuuraTheme.font(17))
                                .foregroundStyle(TsutsuuraTheme.skyInk)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .accessibilityLabel(
                                    "表示名は\(NameValidation.characterCount(displayName))文字、最大\(NameValidation.maximumLength)文字"
                                )
                            }

                            TextRaisedButton(
                                title: isSavingName
                                    ? "保存中…"
                                    : (normalizedDisplayName.isEmpty
                                        ? "名前を入力してください"
                                        : "名前を保存"),
                                height: 58,
                                fontSize: 22,
                                haptic: .success,
                                action: saveDisplayName
                            )
                            .disabled(!canSaveDisplayName)
                            .accessibilityIdentifier("settings-save-button")
                        }

                        if let saveFeedback {
                            Label(saveFeedback, systemImage: "checkmark.circle.fill")
                                .font(TsutsuuraTheme.font(19))
                                .foregroundStyle(TsutsuuraTheme.greenDark)
                                .accessibilityIdentifier("settings-save-feedback")
                        }

                        if let family = profile.family {
                            Label(
                                "\(family.name) · \(family.memberCount)人",
                                systemImage: "person.3.fill"
                            )
                            .font(TsutsuuraTheme.bodyFont(size: 20))
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .foregroundStyle(TsutsuuraTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                }

                if let onPersonalMark {
                    LifecycleNavigationButton(
                        title: "あなたのしるし",
                        subtitle: "名前の横の絵を、指でかいて変える",
                        icon: "pencil.tip.crop.circle",
                        action: {
                            isDisplayNameFocused = false
                            onPersonalMark()
                        }
                    )
                    .accessibilityIdentifier("personal-mark-button")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("よく使う設定")
                        .font(TsutsuuraTheme.bodyFont(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    if let onHelp {
                        LifecycleNavigationButton(
                            title: "使い方を見る",
                            subtitle: "質問への答え方を、ひとつずつ確認",
                            icon: "questionmark.circle.fill",
                            action: onHelp
                        )
                        .accessibilityIdentifier("help-button")
                    }
                    if let onNotificationSettings {
                        LifecycleNavigationButton(
                            title: "お知らせを選ぶ",
                            subtitle: "今日の質問や、家族からの反応",
                            icon: "bell.fill",
                            action: onNotificationSettings
                        )
                        .accessibilityIdentifier("notification-settings-button")
                    }
                    if profile.managed != true {
                        LifecycleNavigationButton(
                            title: "家族を追加・確認する",
                            subtitle: "家族の名前や、iPhoneの準備",
                            icon: "person.3.fill",
                            action: openFamilySettings
                        )
                        .accessibilityIdentifier("family-settings-button")
                    }
                }

                if let onAccountPrivacy {
                    LifecycleNavigationButton(
                        title: "機種変更・データの保存",
                        subtitle: "新しいiPhoneへの引き継ぎなど",
                        icon: "iphone",
                        action: onAccountPrivacy
                    )
                    .accessibilityIdentifier("account-privacy-button")
                }

                DisclosureGroup {
                    VStack(spacing: 18) {
                TextRaisedButton(
                    title: isRefreshingData ? "更新中…" : "データを更新",
                    icon: "arrow.clockwise",
                    height: 64,
                    fontSize: 27,
                    action: refreshData
                )
                .disabled(isRefreshingData)
                .accessibilityIdentifier("settings-refresh-button")

                if let refreshFeedback {
                    Text(refreshFeedback)
                        .font(TsutsuuraTheme.font(19))
                        .foregroundStyle(.white.opacity(0.82))
                        .accessibilityIdentifier("settings-refresh-feedback")
                }

                TextRaisedButton(
                    title: "ログアウト",
                    icon: "rectangle.portrait.and.arrow.right",
                    fill: TsutsuuraTheme.coral,
                    shadow: Color(hex: 0x8B444B),
                    height: 64,
                    fontSize: 27,
                    haptic: .warning,
                    action: { isSignOutConfirmationPresented = true }
                )
                .accessibilityIdentifier("settings-sign-out-button")
                    }
                    .padding(.top, 16)
                } label: {
                    Text("ほかの操作")
                        .font(TsutsuuraTheme.bodyFont(size: 22, weight: .semibold))
                        .frame(minHeight: 56)
                }
                .tint(.white)
                .foregroundStyle(.white)

                Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 44)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            TsutsuuraMotion.respectingReduceMotion(
                reduceMotion,
                TsutsuuraMotion.quickSpring
            ),
            value: isDisplayNameFocused
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("閉じる") {
                    isDisplayNameFocused = false
                }
                .accessibilityIdentifier("dismiss-settings-keyboard")
            }
        }
        .confirmationDialog(
            "ログアウトしますか？",
            isPresented: $isSignOutConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("ログアウト", role: .destructive) {
                onSignOut()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(signOutWarning)
        }
    }

    @ViewBuilder
    private var settingsHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                settingsBackButton
                Text("設定")
                    .font(TsutsuuraTheme.displayFont(34))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack {
                settingsBackButton
                Spacer()
                Text("設定")
                    .font(TsutsuuraTheme.displayFont(34))
                    .foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 67)
            }
        }
    }

    private var settingsBackButton: some View {
        Button {
            HapticPlayer.play(.selection)
            goBack()
        } label: {
            Label("戻る", systemImage: "chevron.left")
                .font(TsutsuuraTheme.displayFont(26))
                .foregroundStyle(.white)
                .frame(minHeight: 54)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func goBack() {
        isDisplayNameFocused = false
        onBack()
    }

    private func saveDisplayName() {
        guard canSaveDisplayName else { return }
        isDisplayNameFocused = false
        isSavingName = true
        Task {
            let didSave = await onSaveName()
            isSavingName = false
            saveFeedback = didSave ? "保存しました" : nil
        }
    }

    private func openFamilySettings() {
        isDisplayNameFocused = false
        onFamilySettings()
    }

    private func refreshData() {
        guard !isRefreshingData else { return }
        isRefreshingData = true
        Task {
            let didRefresh = await onRefresh()
            isRefreshingData = false
            refreshFeedback = didRefresh
                ? "更新しました · \(Self.refreshTimeFormatter.string(from: Date()))"
                : "一部を更新できませんでした。通信を確認して、もう一度お試しください。"
        }
    }

    private static let refreshTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "H:mm"
        return formatter
    }()
}

struct ErrorToast: View {
    let message: String
    let onDismiss: () -> Void

    private var spokenMessage: String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last,
              !["。", "！", "？", ".", "!", "?"].contains(last) else {
            return trimmed
        }
        return trimmed + "。"
    }

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityHidden(true)
                Text(message)
                    .font(TsutsuuraTheme.font(19))
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 388)
            .background(TsutsuuraTheme.coral.opacity(0.98))
            .overlay(Rectangle().stroke(Color.white.opacity(0.45), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("エラー。\(spokenMessage)閉じる")
        .accessibilityHint("ダブルタップしてこのお知らせを閉じます")
        .accessibilityIdentifier("error-toast-dismiss-button")
        .onAppear {
            UIAccessibility.post(
                notification: .announcement,
                argument: "エラー。\(message)"
            )
        }
    }
}

struct SuccessBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)

            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 2)
                              ? TsutsuuraTheme.cyan
                              : TsutsuuraTheme.orange)
                        .frame(width: 9, height: 29)
                        .offset(y: animate && !reduceMotion ? -118 : -32)
                        .rotationEffect(.degrees(Double(index) * 30))
                        .opacity(animate && !reduceMotion ? 0 : 1)
                }

                Circle()
                    .fill(TsutsuuraTheme.cyan)
                    .frame(width: 130, height: 130)
                Image(systemName: "checkmark")
                    .font(.system(size: 62, weight: .black))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
            .scaleEffect(reduceMotion ? 1 : (animate ? 1 : 0.76))

            Text("回答しました!")
                .font(TsutsuuraTheme.displayFont(34))
                .foregroundStyle(.white)
                .offset(y: 126)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("回答しました")
        .onAppear {
            HapticPlayer.play(.success)
            withAnimation(
                TsutsuuraMotion.respectingReduceMotion(
                    reduceMotion,
                    TsutsuuraMotion.emphasizedSpring
                )
            ) {
                animate = true
            }
        }
    }
}

extension View {
    @ViewBuilder
    func tsutsuuraPhoneInputTraits() -> some View {
        #if os(iOS)
        self
            .keyboardType(.phonePad)
            .textContentType(.telephoneNumber)
        #else
        self
        #endif
    }

    @ViewBuilder
    func tsutsuuraOTPInputTraits() -> some View {
        #if os(iOS)
        self
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
        #else
        self
        #endif
    }
}
