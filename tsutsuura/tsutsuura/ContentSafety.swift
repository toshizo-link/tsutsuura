import Foundation
import SwiftUI

struct ContentSafetySnapshot: Codable, Equatable, Sendable {
    var users: [UserProfile] = []
    var hiddenUserIds: [String] = []
    var hiddenAnswerIds: [String] = []
    var hiddenCommentIds: [String] = []
}

struct AnswerReport: Codable, Equatable, Sendable {
    let id: String
    let answerId: String?
    let reason: CommentReportReason?
    let status: String
    let createdAt: Date?
}

struct SafetyMediaOwner: Equatable, Sendable {
    let answerID: String
    let authorID: String
}

struct ContentSafetyState: Equatable, Sendable {
    var blockedUsers: [UserProfile] = []
    var hiddenUserIDs: Set<String> = []
    var hiddenAnswerIDs: Set<String> = []
    var hiddenCommentIDs: Set<String> = []
    var mediaOwners: [String: SafetyMediaOwner] = [:]
    var revision = 0
    var isLoading = false
    var isWorking = false
    var errorMessage: String?
    var feedback: String?

    func allowsMedia(id: String) -> Bool {
        guard let owner = mediaOwners[id] else { return true }
        return !hiddenUserIDs.contains(owner.authorID) && !hiddenAnswerIDs.contains(owner.answerID)
    }

    func allows(_ answer: Answer) -> Bool {
        !hiddenUserIDs.contains(answer.author.id) && !hiddenAnswerIDs.contains(answer.id)
    }
    func allows(_ comment: Comment) -> Bool {
        !hiddenUserIDs.contains(comment.author.id) && !hiddenCommentIDs.contains(comment.id)
            && !hiddenAnswerIDs.contains(comment.answerID)
    }
}

struct ContentSafetyTarget: Equatable {
    let answerID: String
    let commentID: String?
    let author: AnswerAuthor
    var isAnswer: Bool { commentID == nil }
}

extension Notification.Name {
    static let contentSafetyDidChange = Notification.Name("TsutsuuraContentSafetyDidChange")
}

struct ContentSafetyScreen: View {
    let target: ContentSafetyTarget
    let isWorking: Bool
    let feedback: String?
    let errorMessage: String?
    let onBack: () -> Void
    let onReport: (CommentReportReason) -> Void
    let onBlock: () -> Void
    @State private var reason = CommentReportReason.inappropriate
    @State private var confirmsBlock = false
    @State private var lastAction: SafetyAction?
    @State private var reported = false
    @State private var blocked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum SafetyAction { case report, block }

    var body: some View {
        ScrollViewReader { scrollProxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SafetyPageHeader(title: "安心して使う", onBack: onBack)
                PaperPanel {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(target.isAnswer ? "この回答を報告する" : "このコメントを報告する")
                            .font(TsutsuuraTheme.displayFont(27))
                        Text(target.isAnswer
                            ? "回答の文章と、添付された写真・音声をまとめて運営者に報告します。報告した回答は、あなたの画面から非表示になります。"
                            : "コメントを運営者に報告します。報告したコメントは、あなたの画面から非表示になります。")
                        Text("報告者の名前は相手に伝えません。")
                        ForEach(CommentReportReason.allCases, id: \.self) { item in
                            Button { reason = item; HapticPlayer.play(.selection) } label: {
                                HStack {
                                    Image(systemName: reason == item ? "checkmark.circle.fill" : "circle")
                                    Text(reasonTitle(item))
                                    Spacer(minLength: 0)
                                }.frame(minHeight: 48)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(reason == item ? [.isSelected] : [])
                            .accessibilityIdentifier("safety-reason-\(item.rawValue)")
                        }
                        TextRaisedButton(title: reported ? "報告しました" : "報告して非表示にする", icon: reported ? "checkmark" : "flag.fill", height: 64, fontSize: 22) {
                            lastAction = .report
                            onReport(reason)
                        }
                        .disabled(isWorking || reported || blocked)
                        .accessibilityIdentifier("safety-report-submit")
                        actionFeedback(for: .report)
                    }
                    .font(TsutsuuraTheme.bodyFont(size: 20))
                    .foregroundStyle(TsutsuuraTheme.ink)
                    .padding(24)
                }
                PaperPanel {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("\(target.author.displayName)さんをブロック")
                            .font(TsutsuuraTheme.displayFont(25))
                        Text("お互いの回答・コメント・写真・音声を表示しなくなり、反応も届かなくなります。家族の人数は変わりません。設定から解除できます。")
                        TextRaisedButton(title: blocked ? "ブロックしました" : "この人をブロック", icon: blocked ? "checkmark" : "person.crop.circle.badge.xmark", height: 64, fontSize: 24) {
                            confirmsBlock = true
                        }
                        .disabled(isWorking || blocked)
                        .accessibilityIdentifier("safety-block-button")
                        actionFeedback(for: .block)
                    }
                    .font(TsutsuuraTheme.bodyFont(size: 20))
                    .foregroundStyle(TsutsuuraTheme.ink)
                    .padding(24)
                }
            }
            .padding(24)
        }
        .alert("\(target.author.displayName)さんをブロックしますか？", isPresented: $confirmsBlock) {
            Button("ブロックする", role: .destructive) { lastAction = .block; onBlock() }
            Button("戻る", role: .cancel) {}
        } message: {
            Text("相手には通知しません。解除すると、報告済みの内容を除いて再び表示されます。")
        }
        .onChange(of: feedback) { _, value in
            guard value != nil else { return }
            if lastAction == .report { reported = true }
            if lastAction == .block { blocked = true }
            withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion, TsutsuuraMotion.quickSpring)) {
                scrollProxy.scrollTo("safety-action-feedback", anchor: .center)
            }
        }
        .onChange(of: errorMessage) { _, value in
            guard value != nil else { return }
            withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion, TsutsuuraMotion.quickSpring)) {
                scrollProxy.scrollTo("safety-action-feedback", anchor: .center)
            }
        }
        }
    }

    @ViewBuilder
    private func actionFeedback(for action: SafetyAction) -> some View {
        if lastAction == action {
            VStack(alignment: .leading, spacing: 12) {
                if let feedback {
                    Label(feedback, systemImage: "checkmark.circle.fill")
                        .accessibilityIdentifier("safety-feedback")
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .accessibilityIdentifier("safety-error")
                }
            }
            .id("safety-action-feedback")
        }
    }

    private func reasonTitle(_ value: CommentReportReason) -> String {
        switch value {
        case .spam: "迷惑な投稿・宣伝"
        case .harassment: "悪口・嫌がらせ"
        case .privacy: "個人情報・無断で載せた写真"
        case .inappropriate: "不適切な内容"
        case .other: "その他"
        }
    }
}

struct BlockedUsersScreen: View {
    let users: [UserProfile]
    let isWorking: Bool
    let errorMessage: String?
    let onBack: () -> Void
    let onRefresh: () async -> Void
    let onUnblock: (String) -> Void
    @State private var pendingUser: UserProfile?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SafetyPageHeader(title: "ブロックした人", onBack: onBack)
                Text("ブロックした人は、家族から退会しません。解除すると、お互いの投稿や反応が再び表示されます。報告した内容は非表示のままです。")
                    .font(TsutsuuraTheme.bodyFont(size: 21)).foregroundStyle(.white)
                if users.isEmpty {
                    PaperPanel {
                        Text("ブロックした人はいません")
                            .font(TsutsuuraTheme.bodyFont(size: 23))
                            .foregroundStyle(TsutsuuraTheme.ink)
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ForEach(users) { user in
                    PaperPanel {
                        VStack(alignment: .leading, spacing: 18) {
                            PersonBadge(name: user.displayName, mark: user.avatarMark, nameColor: TsutsuuraTheme.ink)
                            TextRaisedButton(title: "ブロックを解除", icon: "person.crop.circle.badge.checkmark", height: 60, fontSize: 24) {
                                pendingUser = user
                            }
                            .disabled(isWorking)
                            .accessibilityIdentifier("unblock-user-\(user.id)")
                        }
                        .padding(24)
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.white) }
                TextRaisedButton(title: "一覧を更新", icon: "arrow.clockwise", height: 60, fontSize: 24) { Task { await onRefresh() } }
                    .disabled(isWorking).accessibilityIdentifier("blocked-users-refresh")
            }.padding(24)
        }
        .task { await onRefresh() }
        .alert("ブロックを解除しますか？", isPresented: Binding(get: { pendingUser != nil }, set: { if !$0 { pendingUser = nil } }), presenting: pendingUser) { user in
            Button("解除する") { pendingUser = nil; onUnblock(user.id) }
            Button("戻る", role: .cancel) { pendingUser = nil }
        } message: { user in
            Text("\(user.displayName)さんと、お互いの投稿や反応が再び表示されます。")
        }
    }
}

private struct SafetyPageHeader: View {
    let title: String
    let onBack: () -> Void
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { back; Spacer(); heading }
            VStack(alignment: .leading, spacing: 16) { back; heading }
        }.foregroundStyle(.white)
    }
    private var heading: some View {
        Text(title).font(TsutsuuraTheme.displayFont(32)).accessibilityAddTraits(.isHeader)
    }
    private var back: some View {
        Button(action: onBack) { Label("戻る", systemImage: "chevron.left").frame(minHeight: 52) }
            .font(TsutsuuraTheme.displayFont(24)).buttonStyle(.plain)
            .accessibilityIdentifier("lifecycle-back-button")
    }
}
