import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Pairing links

/// Strictly validates pairing links before a credential is handed to the
/// session store. Keeping this parser pure makes Universal Link and QR behavior
/// deterministic in unit tests without requiring a signed device build.
enum PairingLinkParser {
    static let productionHost = "toshizo.link"
    static let productionPathPrefix = ["tsutsuura-api", "api", "invite"]

    static func token(from url: URL) -> String? {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        guard components.user == nil, components.password == nil else {
            return nil
        }

        let candidate: String?
        switch components.scheme?.lowercased() {
        case "tsutsuura":
            guard components.host?.lowercased() == "pair" else {
                return nil
            }
            let pathParts = normalizedPathParts(components.path)
            if pathParts.count == 1 {
                candidate = pathParts[0]
            } else if pathParts.isEmpty {
                candidate = components.queryItems?
                    .first(where: { $0.name == "token" })?
                    .value
            } else {
                return nil
            }

        case "https":
            guard components.host?.lowercased() == productionHost,
                  components.port == nil,
                  normalizedPathParts(components.path).count
                    == productionPathPrefix.count + 1 else {
                return nil
            }
            let pathParts = normalizedPathParts(components.path)
            guard Array(pathParts.dropLast()) == productionPathPrefix else {
                return nil
            }
            candidate = pathParts.last

        default:
            return nil
        }

        guard let candidate else { return nil }
        let decoded = candidate.removingPercentEncoding ?? candidate
        guard (40...128).contains(decoded.utf8.count),
              decoded.unicodeScalars.allSatisfy(isASCIITokenCharacter) else {
            return nil
        }
        return decoded
    }

    private static func isASCIITokenCharacter(
        _ scalar: Unicode.Scalar
    ) -> Bool {
        switch scalar.value {
        case 45, 48...57, 65...90, 95, 97...122:
            return true
        default:
            return false
        }
    }

    private static func normalizedPathParts(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}

// MARK: - Push destinations

enum AppPushDestination: Equatable, Sendable, Codable {
    case todayQuestion(questionID: String?)
    case familyAnswer(answerID: String)
    case comments(answerID: String, commentID: String?)

    static func parse(_ userInfo: [AnyHashable: Any]) -> AppPushDestination? {
        guard let destination = userInfo["destination"] as? String else {
            return nil
        }

        switch destination {
        case "today_question":
            if let rawQuestionID = userInfo["question_id"] {
                guard let questionID = cleanIdentifier(rawQuestionID) else {
                    return nil
                }
                return .todayQuestion(questionID: questionID)
            }
            return .todayQuestion(questionID: nil)

        case "family_answer":
            guard let answerID = cleanIdentifier(userInfo["answer_id"]) else {
                return nil
            }
            return .familyAnswer(answerID: answerID)

        case "comments":
            guard let answerID = cleanIdentifier(userInfo["answer_id"]) else {
                return nil
            }
            let commentID: String?
            if let rawCommentID = userInfo["comment_id"] {
                guard let cleaned = cleanIdentifier(rawCommentID) else {
                    return nil
                }
                commentID = cleaned
            } else {
                commentID = nil
            }
            return .comments(answerID: answerID, commentID: commentID)

        default:
            return nil
        }
    }

    private static func cleanIdentifier(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 128 else { return nil }
        return cleaned
    }
}

/// Preserves a notification tap that arrives before SwiftUI has installed its
/// observers (cold launch) or while the user is signed out. The destination is
/// deliberately tiny and contains no notification body or private family data.
actor PendingPushDestinationStore {
    static let shared = PendingPushDestinationStore()

    private static let defaultStorageKey = "pending-push-destination-v1"
    private let defaults: UserDefaults
    private let storageKey: String
    private var destination: AppPushDestination?

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = PendingPushDestinationStore.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey) {
            destination = try? JSONDecoder().decode(
                AppPushDestination.self,
                from: data
            )
        }
    }

    func save(_ newDestination: AppPushDestination) {
        destination = newDestination
        if let data = try? JSONEncoder().encode(newDestination) {
            defaults.set(data, forKey: storageKey)
        }
    }

    func peek() -> AppPushDestination? {
        destination
    }

    /// Removes only the destination that actually finished navigating. If a
    /// newer notification arrives while the earlier one is loading, its value
    /// remains durable for the next pass.
    func acknowledge(_ completed: AppPushDestination) {
        guard destination == completed else { return }
        destination = nil
        defaults.removeObject(forKey: storageKey)
    }
}

enum PushTokenEncoder {
    static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Share presentation

#if canImport(UIKit)
struct ActivityShareButton<Label: View>: View {
    let items: [Any]
    @ViewBuilder let label: () -> Label
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label()
        }
        .sheet(isPresented: $isPresented) {
            ActivityViewController(items: items)
                .ignoresSafeArea()
        }
    }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
#endif
