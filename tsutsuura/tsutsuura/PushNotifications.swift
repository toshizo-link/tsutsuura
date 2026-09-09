import Foundation

#if canImport(UIKit) && canImport(UserNotifications)
import UIKit
import UserNotifications
#endif

extension Notification.Name {
    static let didReceivePushToken = Notification.Name(
        "tsutsuura.didReceivePushToken"
    )
    static let didOpenTodayQuestion = Notification.Name(
        "tsutsuura.didOpenTodayQuestion"
    )
    static let didOpenPushDestination = Notification.Name(
        "tsutsuura.didOpenPushDestination"
    )
}

enum PushAuthorizationState: String, Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unavailable
}

#if canImport(UIKit) && canImport(UserNotifications)
enum PushNotificationRegistration {
    #if DEBUG
    // UI tests exercise both choices without changing the simulator's real
    // permission or producing a token that belongs to a demo account.
    @MainActor private static var testingAuthorization: PushAuthorizationState? = {
        let environment = ProcessInfo.processInfo.environment
        guard environment["UI_TESTING"] == "1",
              let value = environment["TSUTSUURA_TEST_PUSH_AUTHORIZATION"] else { return nil }
        return PushAuthorizationState(rawValue: value)
    }()
    #endif

    static func authorizationState() async -> PushAuthorizationState {
        #if DEBUG
        if let state = await MainActor.run(body: { testingAuthorization }) { return state }
        #endif
        let settings = await UNUserNotificationCenter.current()
            .notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        @unknown default:
            return .unavailable
        }
    }

    @discardableResult
    static func requestAuthorizationIfNeeded() async -> PushAuthorizationState {
        #if DEBUG
        if let state = await MainActor.run(body: { () -> PushAuthorizationState? in
            guard let state = testingAuthorization else { return nil }
            if state == .notDetermined {
                let response = ProcessInfo.processInfo.environment["TSUTSUURA_TEST_PUSH_RESPONSE"] ?? "authorized"
                testingAuthorization = PushAuthorizationState(rawValue: response) ?? .denied
            }
            return testingAuthorization
        }) { return state }
        #endif
        guard DemoLaunchMode.current() == nil,
              ProcessInfo.processInfo.environment["UI_TESTING"] != "1" else {
            return .authorized
        }

        let center = UNUserNotificationCenter.current()
        let before = await authorizationState()
        if before == .notDetermined {
            do {
                _ = try await center.requestAuthorization(
                    options: [.alert, .badge, .sound]
                )
            } catch {
                return await authorizationState()
            }
        }
        let after = await authorizationState()
        if after == .authorized || after == .provisional {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return after
    }

    @discardableResult
    static func registerIfAuthorized() async -> PushAuthorizationState {
        #if DEBUG
        if let state = await MainActor.run(body: { testingAuthorization }) { return state }
        #endif
        guard DemoLaunchMode.current() == nil,
              ProcessInfo.processInfo.environment["UI_TESTING"] != "1" else {
            return .authorized
        }
        let state = await authorizationState()
        if state == .authorized || state == .provisional {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return state
    }

    static func requestAuthorization() {
        Task {
            _ = await requestAuthorizationIfNeeded()
        }
    }

    @MainActor
    static func unregister() {
        UIApplication.shared.unregisterForRemoteNotifications()
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [
            UIApplication.LaunchOptionsKey: Any
        ]? = nil
    ) -> Bool {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = PushTokenEncoder.hexString(from: deviceToken)
        NotificationCenter.default.post(
            name: .didReceivePushToken,
            object: token
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = response.notification.request.content.userInfo
        guard let destination = AppPushDestination.parse(payload) else {
            return
        }
        await PendingPushDestinationStore.shared.save(destination)
        NotificationCenter.default.post(
            name: .didOpenPushDestination,
            object: destination
        )
        if case .todayQuestion = destination {
            NotificationCenter.default.post(
                name: .didOpenTodayQuestion,
                object: nil
            )
        }
    }
}
#else
enum PushNotificationRegistration {
    static func authorizationState() async -> PushAuthorizationState {
        .unavailable
    }
    static func requestAuthorizationIfNeeded() async -> PushAuthorizationState {
        .unavailable
    }
    static func registerIfAuthorized() async -> PushAuthorizationState {
        .unavailable
    }
    static func requestAuthorization() {}
    static func unregister() {}
}
final class AppDelegate: NSObject {}
#endif
