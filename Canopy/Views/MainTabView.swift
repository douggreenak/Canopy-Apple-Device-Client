import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "square.grid.2x2.fill", value: AppTab.dashboard) {
                DashboardView()
            }
            Tab("Schedule", systemImage: "calendar", value: AppTab.schedule) {
                ScheduleView()
            }
            Tab("Homework", systemImage: "book.closed.fill", value: AppTab.homework) {
                HomeworkView()
            }
            Tab("Tasks", systemImage: "checkmark.circle.fill", value: AppTab.tasks) {
                TasksView()
            }
            Tab("Grades", systemImage: "chart.bar.fill", value: AppTab.grades) {
                GradesView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        #if os(macOS)
        // macOS: the toolbar area sits above CanopyBackground so needs its own
        // material. Using .ultraThinMaterial keeps it consistent without
        // fighting the system's glass capsule compositor.
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        #endif
        // iOS: no UITabBarAppearance and no .toolbarBackground override —
        // letting the OS render the liquid-glass capsule uninterrupted.
    }
}

enum AppTab: Hashable {
    case dashboard, schedule, homework, tasks, grades, settings
}
