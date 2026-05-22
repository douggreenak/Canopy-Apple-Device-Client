import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(CanopyStore.self) private var store
    @State private var checkingSession = true

    var body: some View {
        Group {
            if checkingSession {
                splashView
            } else if authStore.isLoggedIn {
                MainTabView()
                    .task { await store.loadAll() }
            } else {
                LoginView()
            }
        }
        .task {
            await authStore.checkSession()
            checkingSession = false
        }
    }

    private var splashView: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "tree.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.canopyGreen)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Canopy")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                ProgressView()
                    .padding(.top, 4)
            }
        }
    }
}
