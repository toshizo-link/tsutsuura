import Foundation

/// Timezone belongs to a signed-in account even when notifications are denied.
/// Serialize updates and retain the newest desired value across an in-flight
/// change; failures are retried on a later activation instead of looping.
@MainActor
final class DeviceTimeZoneSynchronizer {
    struct Identity: Equatable {
        let userID: String
        let sessionGeneration: Int
        let timeZoneIdentifier: String
    }

    private var desired: Identity?
    private var acknowledged: Identity?
    private var isSynchronizing = false

    func reset() {
        desired = nil
        acknowledged = nil
    }

    func synchronize(
        identity: Identity,
        using update: (Identity) async -> Bool
    ) async {
        desired = identity
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }

        while let request = desired, request != acknowledged {
            let succeeded = await update(request)
            guard desired == request else { continue }
            if succeeded { acknowledged = request }
            return
        }
    }
}
