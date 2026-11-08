import Foundation
import Observation

/// Top-level destinations (web nav: Dashboard, Classes, Schedule, Grades,
/// Exams, Tasks, Settings).
enum AppTab: String, Hashable, CaseIterable, Identifiable {
    var id: String { rawValue }
    case dashboard, classes, schedule, homework, grades, exams, settings
}

/// App-wide navigation state so any view (dashboard summary cards, warning
/// banners, keyboard shortcuts) can jump to a tab without prop-drilling.
@MainActor
@Observable
final class AppNavigation {
    static let shared = AppNavigation()
    var selectedTab: AppTab = .dashboard
    /// When set, the Schedule tab should open on this date (yyyy-MM-dd) in Day view.
    var scheduleDate: String?
    /// When set, Settings should scroll to / open this section (e.g. "powerschool").
    var settingsSection: String?
    /// When set, Grades should open this class's detail.
    var gradesClassId: String?
    /// Toggles the keyboard-shortcuts help sheet.
    var showKeyboardShortcuts = false

    func go(_ tab: AppTab) { selectedTab = tab }
    func goToSchedule(date: String? = nil) { scheduleDate = date; selectedTab = .schedule }
    func goToSettings(section: String? = nil) { settingsSection = section; selectedTab = .settings }
    func goToGrades(classId: String? = nil) { gradesClassId = classId; selectedTab = .grades }
}
