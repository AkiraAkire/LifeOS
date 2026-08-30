import Combine
import Foundation

/// Top-level destinations shown in the macOS sidebar.
enum AppDestination: String, CaseIterable, Identifiable {
    case today
    case calendar
    case tasks
    case timetable
    case courses
    case journal
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "今天"
        case .calendar: "日历"
        case .tasks: "任务"
        case .timetable: "课表"
        case .courses: "课程"
        case .journal: "日记"
        case .settings: "设置"
        }
    }

    var symbolName: String {
        switch self {
        case .today: "sun.max"
        case .calendar: "calendar"
        case .tasks: "checklist"
        case .timetable: "tablecells"
        case .courses: "graduationcap"
        case .journal: "book.closed"
        case .settings: "gearshape"
        }
    }
}

/// Coordinates explicit cross-module routes without turning date selections
/// into persisted state. Calendar and Journal consume the requested date when
/// they become visible, then continue to use their own local selection.
final class AppNavigationCoordinator: ObservableObject {
    @Published var destination: AppDestination = .today
    @Published private var requestedCalendarDate: Date?
    @Published private var requestedJournalDate: Date?

    func showCalendar(on date: Date) {
        requestedCalendarDate = date
        destination = .calendar
    }

    func showJournal(on date: Date) {
        requestedJournalDate = date
        destination = .journal
    }

    func showTasks() {
        destination = .tasks
    }

    func takeRequestedCalendarDate() -> Date? {
        defer { requestedCalendarDate = nil }
        return requestedCalendarDate
    }

    func takeRequestedJournalDate() -> Date? {
        defer { requestedJournalDate = nil }
        return requestedJournalDate
    }
}
