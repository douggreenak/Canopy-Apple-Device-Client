import SwiftUI

@main
struct CanopyApp: App {
    @State private var authStore = AuthStore()
    @State private var store = CanopyStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authStore)
                .environment(store)
                .makeWindowTransparent()
        }
    }
}
