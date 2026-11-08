import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(CanopyStore.self) private var store
    @Environment(\.colorScheme) private var systemScheme
    @State private var checkingSession = true
    @State private var showWizard = false
    @State private var wizardRequired = false
    @AppStorage("colorScheme") private var colorSchemeRaw = "system"
    @AppStorage("accentPreset") private var accentPresetRaw = AccentPalette.defaultAccent
    @AppStorage("sp-wizard-dismissed") private var wizardDismissed = false

    private var preferredScheme: ColorScheme? {
        switch colorSchemeRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    /// The scheme actually rendering, so the accent gets its light/dark calibration.
    private var resolvedScheme: ColorScheme { preferredScheme ?? systemScheme }

    var body: some View {
        Group {
            if checkingSession {
                splashView
            } else if authStore.isLoggedIn {
                if authStore.isAdmin {
                    AdminDashboardView()
                } else {
                    MainTabView()
                        .task {
                            await store.loadAll()
                            // Bridge server-stored appearance prefs into local @AppStorage.
                            if let accent = store.settings.accentColor, !accent.isEmpty { accentPresetRaw = AccentPalette.name(for: accent) }
                            if let theme = store.settings.themeMode, !theme.isEmpty { colorSchemeRaw = theme }
                            await evaluateWizardTrigger()
                        }
                        .onChange(of: authStore.isLoggedIn) { _, loggedIn in
                            if !loggedIn { store.clearAll() }
                        }
                        #if os(iOS)
                        .fullScreenCover(isPresented: $showWizard) {
                            SetupWizardView(required: wizardRequired)
                        }
                        #else
                        .sheet(isPresented: $showWizard) {
                            SetupWizardView(required: wizardRequired)
                                .frame(minWidth: 640, minHeight: 620)
                        }
                        #endif
                        .onReceive(NotificationCenter.default.publisher(for: .openSetupWizard)) { _ in
                            wizardRequired = false
                            showWizard = true
                        }
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
        .tint(AccentPalette.resolve(accentPresetRaw).color(for: resolvedScheme))
    }

    // MARK: - Setup Wizard trigger
    // Required + non-dismissible on a fresh registration (web: `isNew &&
    // role !== 'admin'`). Otherwise auto-opens when the server's setup health
    // check fails and the user hasn't dismissed it before (web AppShell).
    private func evaluateWizardTrigger() async {
        if authStore.justRegistered {
            wizardRequired = true
            showWizard = true
            authStore.consumeJustRegistered()
            return
        }
        guard !wizardDismissed else { return }
        if let health = try? await APIClient.shared.getHealth(), !health.ok {
            wizardRequired = false
            showWizard = true
            return
        }
        // Also nudge a brand-new account that has nothing set up yet.
        let looksIncomplete = store.classes.isEmpty && (store.settings.schoolName?.isEmpty ?? true)
            && !(store.setupStatus?.hasPowerschool ?? false)
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
