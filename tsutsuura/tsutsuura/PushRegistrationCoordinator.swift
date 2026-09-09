import Foundation

/// Device permission belongs to this installation; upload acknowledgments also
/// belong to an account. Serialize uploads so a late result cannot discard a
/// newer device token or mark another account's registration as complete.
@MainActor
final class PushRegistrationCoordinator {
    private struct Identity: Equatable {
        let userID: String
        let token: String
        let sessionGeneration: Int
    }

    private var userID: String?
    private var token: String?
    private var sessionGeneration = 0
    private var acknowledged: Identity?
    private var authorization: PushAuthorizationState = .unavailable
    private var isRefreshingAuthorization = false
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    private var isUploading = false

    func setUserID(_ value: String?) {
        guard userID != value else { return }
        userID = value
        sessionGeneration += 1
        acknowledged = nil
        if value == nil { token = nil }
    }

    func receiveToken(_ value: String) {
        guard !value.isEmpty else { return }
        token = value
    }

    /// The caller invokes this on foreground activation, including returning
    /// from iOS Settings. Concurrent view/session callbacks share one request.
    func refreshAuthorization(
        requestsPermission: Bool = false,
        using refresh: () async -> PushAuthorizationState
    ) async -> PushAuthorizationState? {
        if isRefreshingAuthorization {
            // A deliberate opt-in must not disappear behind a passive
            // foreground query. Only passive duplicate queries are coalesced.
            guard requestsPermission else { return nil }
            await withCheckedContinuation { authorizationWaiters.append($0) }
            guard !Task.isCancelled else { return nil }
            return await refreshAuthorization(requestsPermission: true, using: refresh)
        }
        isRefreshingAuthorization = true
        defer {
            isRefreshingAuthorization = false
            let waiters = authorizationWaiters
            authorizationWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
        let state = await refresh()
        authorization = state
        if state != .authorized && state != .provisional {
            acknowledged = nil
        }
        return state
    }

    func synchronize(
        using upload: (_ token: String, _ userID: String) async -> Bool
    ) async {
        guard !isUploading else { return }
        isUploading = true
        defer { isUploading = false }

        while let desired = desiredIdentity, desired != acknowledged {
            let succeeded = await upload(desired.token, desired.userID)
            // If the account/token changed during the request, finish the
            // newest registration before treating this drain as complete.
            guard desiredIdentity == desired else { continue }
            if succeeded { acknowledged = desired }
            return
        }
    }

    private var desiredIdentity: Identity? {
        guard authorization == .authorized || authorization == .provisional,
              let userID, let token else { return nil }
        return Identity(userID: userID, token: token, sessionGeneration: sessionGeneration)
    }
}

/// Foreground, cold-launch and notification callbacks can arrive together.
/// Open one destination at a time, then pick up a newer tap that arrived while
/// its predecessor was loading. A failed request remains stored for a later
/// foreground attempt instead of spinning on an unavailable connection.
@MainActor
final class PushDestinationCoordinator {
    private var isOpening = false

    func consume(
        from pending: PendingPushDestinationStore,
        isAvailable: () -> Bool,
        open: (AppPushDestination) async -> Bool
    ) async {
        guard !isOpening else { return }
        isOpening = true
        defer { isOpening = false }

        while let destination = await pending.peek() {
            guard isAvailable(), !Task.isCancelled else { return }
            let handled = await open(destination)
            guard isAvailable(), !Task.isCancelled else { return }
            if handled {
                await pending.acknowledge(destination)
            } else if await pending.peek() == destination {
                return
            }
        }
    }
}
