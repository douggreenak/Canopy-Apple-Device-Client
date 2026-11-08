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
                    WatchPairingView()
                }
            }
            .environment(store)
            .task {
                // Pick up whatever the iPhone already pushed, then refresh.
                WatchPhoneLink.shared.attach(store: store)
                await store.restore()
                checking = false
            }
        }
    }
}
