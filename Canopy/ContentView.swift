import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(CanopyStore.self) private var store
    @State private var checkingSession = true
    @State private var showWizard = false
    @State private var wizardRequired = false
    @AppStorage("colorScheme") private var colorSchemeRaw = "system"
    @AppStorage("accentColor") private var accentColorRaw = AccentPalette.defaultAccent
    @AppStorage("sp-wizard-dismissed") private var wizardDismissed = false

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
                        evaluateWizardTrigger()
                    }
                    .fullScreenCover(isPresented: $showWizard) {
                        SetupWizardView(required: wizardRequired)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .openSetupWizard)) { _ in
                        wizardRequired = false
                        showWizard = true
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

    // MARK: - Setup Wizard trigger
    // Required + non-dismissible on a fresh registration (mirrors web's
    // `isNew && role !== 'admin'` gate). Otherwise auto-opens once per install
    // when setup looks incomplete and the user hasn't dismissed it before —
    // mirrors web's `/api/setup/health` check + `sp-wizard-dismissed` flag.
    private func evaluateWizardTrigger() {
        if authStore.justRegistered {
            wizardRequired = true
            showWizard = true
            authStore.consumeJustRegistered()
            return
        }
        guard !wizardDismissed else { return }
        let looksIncomplete = store.classes.isEmpty && (store.settings.schoolName?.isEmpty ?? true)
        if looksIncomplete {
            wizardRequired = false
            showWizard = true
        }
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
