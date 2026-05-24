import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .dashboard
    #if os(iOS)
    @SceneStorage("canopy.tabCustomization") private var tabCustomization = TabViewCustomization()
    #endif

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "square.grid.2x2.fill", value: AppTab.dashboard) {
                DashboardView()
            }
            .customizationID("canopy.dashboard")

            Tab("Schedule", systemImage: "calendar", value: AppTab.schedule) {
                ScheduleView()
            }
            .customizationID("canopy.schedule")

            Tab("Planner", systemImage: "list.bullet.clipboard.fill", value: AppTab.homework) {
                HomeworkView()
            }
            .customizationID("canopy.planner")

            Tab("Grades", systemImage: "chart.bar.fill", value: AppTab.grades) {
                GradesView()
            }
            .customizationID("canopy.grades")

            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
            .customizationID("canopy.settings")
        }
        #if os(iOS)
        // Enables the built-in "Edit" button in the More tab so users can
        // drag tabs in/out of the bottom bar to their preference.
        .tabViewCustomization($tabCustomization)
        #endif
        #if os(macOS)
        // macOS: keep toolbar area transparent to match CanopyBackground.
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        #endif
    }
}

enum AppTab: Hashable {
    case dashboard, schedule, homework, grades, settings
}
