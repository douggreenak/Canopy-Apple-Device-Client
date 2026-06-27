import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(CanopyStore.self) private var store
    @State private var checkingSession = true
    @AppStorage("colorScheme") private var colorSchemeRaw = "system"
    @AppStorage("accentColor") private var accentColorRaw = AccentPalette.defaultAccent

    private var preferredScheme: ColorScheme? {
        switch colorSchemeRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some View {
        Group {
            if checkingSession {
                splashView
            } else if authStore.isLoggedIn {
                MainTabView()
                    .task {
                        await store.loadAll()
                        // Bridge server-stored appearance prefs into local @AppStorage
                        if let accent = store.settings.accentColor, !accent.isEmpty { accentColorRaw = accent }
                        if let theme = store.settings.themeMode, !theme.isEmpty { colorSchemeRaw = theme }
                    }
            } else {
                LoginView()
            }
        }
        .task {
            await authStore.checkSession()
            checkingSession = false
        }
        .preferredColorScheme(preferredScheme)
        .tint(Color(hex: accentColorRaw))
    }

    private var splashView: some View {
        ZStack {
            CanopyBackground()
            VStack(spacing: 20) {
                CanopyIconView(size: 80)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Canopy")
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)
                ProgressView()
                    .padding(.top, 4)
            }
        }
    }
}
