import SwiftUI

// Port of web src/components/AppShell.tsx: the 7 nav destinations (Dashboard,
// Classes, Schedule, Grades, Exams, Tasks, Settings), the global thin progress
// bar, the save-status indicator, and the keyboard shortcuts (⌘1…⌘7, ⌘/).
//
// On a compact (iPhone) layout the bottom bar keeps the five core tabs so
// Planner and Settings never fall into "More"; Classes and Exams open as
// full sheets from the dashboard cards, the Schedule empty state, Settings ▸
// Manage, or ⌘2/⌘5. On iPad and macOS the sidebar lists all seven.
struct MainTabView: View {
    @Environment(CanopyStore.self) private var store
    @Bindable private var nav = AppNavigation.shared
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    @SceneStorage("canopy.tabCustomization") private var tabCustomization = TabViewCustomization()
    #endif
    @State private var lastBarTab: AppTab = .dashboard
    @State private var compactSheet: AppTab?

    private var isCompact: Bool {
        #if os(iOS)
        return sizeClass == .compact
        #else
        return false
        #endif
    }

    var body: some View {
        TabView(selection: $nav.selectedTab) {
            Tab("Dashboard", systemImage: "square.grid.2x2.fill", value: AppTab.dashboard) {
                DashboardView()
            }
            .customizationID("canopy.dashboard")

            if !isCompact {
                Tab("Classes", systemImage: "books.vertical.fill", value: AppTab.classes) {
                    ClassesTabView()
                }
                .customizationID("canopy.classes")
            }

            Tab("Schedule", systemImage: "calendar", value: AppTab.schedule) {
                ScheduleView()
            }
            .customizationID("canopy.schedule")

            Tab("Grades", systemImage: "chart.bar.fill", value: AppTab.grades) {
                GradesView()
            }
            .customizationID("canopy.grades")

            if !isCompact {
                Tab("Exams", systemImage: "doc.text.magnifyingglass", value: AppTab.exams) {
                    ExamsTabView()
                }
                .customizationID("canopy.exams")
            }

            Tab("Planner", systemImage: "list.bullet.clipboard.fill", value: AppTab.homework) {
                HomeworkView()
            }
            .customizationID("canopy.planner")

            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
            .customizationID("canopy.settings")
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(iOS)
        .tabViewCustomization($tabCustomization)
        #endif
        #if os(macOS)
        // macOS: keep toolbar area transparent to match CanopyBackground.
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        #endif
        // On iPhone, Classes/Exams aren't bar tabs: present them as sheets and
        // keep the bar on the tab the user was on.
        .onChange(of: nav.selectedTab, initial: true) { _, tab in
            if isCompact && (tab == .classes || tab == .exams) {
                compactSheet = tab
                nav.selectedTab = lastBarTab
            } else {
                lastBarTab = tab
            }
        }
        .sheet(item: $compactSheet) { which in
            NavigationStack {
                Group {
                    if which == .classes { ManageClassesView() } else { ManageExamsView() }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { compactSheet = nil } }
                }
            }
        }
        // Thin global loading indicator, mirroring web's LoadingOverlay — a
        // top-of-screen progress bar driven by any in-flight request.
        .overlay(alignment: .top) {
            if store.isLoading || store.isSyncing {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                    .frame(height: 2)
                    .clipped()
                    .transition(.opacity)
            }
        }
        // Web SaveStatusIndicator — top-right, just under the progress bar.
        .overlay(alignment: .topTrailing) {
            SaveStatusIndicatorView()
                .padding(.top, 6)
                .padding(.trailing, 12)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.2), value: store.isLoading || store.isSyncing)
        // Invisible buttons carrying the ⌘ shortcuts (web GlobalShortcuts).
        .background { shortcutButtons }
        .sheet(isPresented: $nav.showKeyboardShortcuts) {
            KeyboardShortcutsSheet()
        }
        .onAppear { PowerSchoolSyncStore.shared.subscribe() }
        .onDisappear { PowerSchoolSyncStore.shared.unsubscribe() }
    }

    /// ⌘1…⌘7 jump to a tab; ⌘/ toggles the Keyboard Shortcuts sheet. Rendered
    /// at zero size so they never affect layout or hit testing.
    private var shortcutButtons: some View {
        Group {
            ForEach(Array(KeyboardShortcuts.navTabs.enumerated()), id: \.offset) { i, item in
                Button(item.label) { nav.go(item.tab) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            Button("Keyboard Shortcuts") { nav.showKeyboardShortcuts.toggle() }
                .keyboardShortcut("/", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
