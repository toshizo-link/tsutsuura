import SwiftUI

@main
@MainActor
struct tsutsuuraApp: App {
    @StateObject private var store: AppStore

    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        _store = StateObject(
            wrappedValue: AppStoreLaunchFactory.make()
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
