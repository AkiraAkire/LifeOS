import Foundation
import SwiftData

/// A weekly course rule. Display instances are calculated for a requested date range instead of stored.
@Model
final class CourseSession {
    @Attribute(.unique) var id: UUID
    var weekdayRaw: Int
    var startTimeMinutes: Int
    var endTimeMinutes: Int
    var startDate: Date
    var endDate: Date?
    var classroomOverride: String?
    var recurrenceEnabled: Bool
    /// Optional for a lightweight SwiftData migration from the original weekly-only rule.
    var weekPatternRaw: String?

    var course: Course?

    var weekday: Weekday {
        get { Weekday(rawValue: weekdayRaw) ?? .monday }
        set { weekdayRaw = newValue.rawValue }
    }

    var weekPattern: WeekPattern {
        get { WeekPattern(rawValue: weekPatternRaw ?? "") ?? .all }
        set { weekPatternRaw = newValue.rawValue }
    }

    init(
        weekday: Weekday,
        startTimeMinutes: Int,
        endTimeMinutes: Int,
        startDate: Date,
        endDate: Date? = nil,
        classroomOverride: String? = nil,
        recurrenceEnabled: Bool = true,
        weekPattern: WeekPattern = .all,
        course: Course? = nil
    ) {
        id = UUID()
        weekdayRaw = weekday.rawValue
        self.startTimeMinutes = startTimeMinutes
        self.endTimeMinutes = endTimeMinutes
        self.startDate = startDate
        self.endDate = endDate
        self.classroomOverride = classroomOverride
        self.recurrenceEnabled = recurrenceEnabled
        weekPatternRaw = weekPattern.rawValue
        self.course = course
    }
}

/// Provides a stable Monday-first presentation order for recurring sessions.
enum CourseSessionOrdering {
    static func sorted(_ sessions: [CourseSession]) -> [CourseSession] {
        sessions.sorted { lhs, rhs in
            let lhsWeekday = weekdayIndex(lhs.weekday)
            let rhsWeekday = weekdayIndex(rhs.weekday)
            if lhsWeekday != rhsWeekday { return lhsWeekday < rhsWeekday }
            if lhs.startTimeMinutes != rhs.startTimeMinutes {
                return lhs.startTimeMinutes < rhs.startTimeMinutes
            }
            if lhs.endTimeMinutes != rhs.endTimeMinutes {
                return lhs.endTimeMinutes < rhs.endTimeMinutes
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func weekdayIndex(_ weekday: Weekday) -> Int {
        (weekday.rawValue + 5) % 7
    }
}
