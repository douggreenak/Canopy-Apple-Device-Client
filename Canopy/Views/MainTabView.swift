import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "square.grid.2x2.fill") {
                DashboardView()
            }
            Tab("Schedule", systemImage: "calendar") {
                ScheduleView()
            }
            Tab("Homework", systemImage: "book.closed.fill") {
                HomeworkView()
            }
            Tab("Tasks", systemImage: "checkmark.circle.fill") {
                TasksView()
            }
            Tab("Grades", systemImage: "chart.bar.fill") {
                GradesView()
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        .tint(.canopyGreen)
    }
}
