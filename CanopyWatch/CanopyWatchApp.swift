import SwiftUI

@main
struct CanopyWatchApp: App {
    @State private var store = WatchStore()
    @State private var checking = true

    var body: some Scene {
        WindowGroup {
            Group {
                if checking {
                    ProgressView()
                } else if store.isLoggedIn {
                    WatchRootView()
                } else {
                    WatchLoginView()
                }
            }
            .environment(store)
            .task {
                await store.restore()
                checking = false
            }
        }
    }
}
