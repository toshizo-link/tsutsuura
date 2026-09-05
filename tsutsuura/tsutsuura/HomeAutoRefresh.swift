import Foundation

/// The owning SwiftUI task cancels when Home disappears or the app becomes
/// inactive. Awaiting each refresh prevents overlapping requests on slow links.
enum HomeAutoRefresh {
    @MainActor
    static func run(
        interval: Duration = .seconds(10),
        refresh: @MainActor () async -> Void
    ) async {
        while !Task.isCancelled {
            do { try await Task.sleep(for: interval) }
            catch { return }
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }
}
