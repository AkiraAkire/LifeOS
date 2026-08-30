import Foundation
import SwiftData

/// A course is the information center for recurring sessions, assignments, exams, and related tasks.
@Model
final class Course {
    @Attribute(.unique) var id: UUID
    var name: String
    var instructor: String?
    var classroom: String?
    var colorHex: String
    var semester: String?
    var note: String?
    /// Nil values mean that this course follows the timetable semester range.
    var startDateOverride: Date?
    var endDateOverride: Date?
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool

    @Relationship(deleteRule: .cascade, inverse: \CourseSession.course) var sessions: [CourseSession] = []
    @Relationship(deleteRule: .cascade, inverse: \Assignment.course) var assignments: [Assignment] = []
    @Relationship(deleteRule: .cascade, inverse: \Exam.course) var exams: [Exam] = []
    @Relationship(inverse: \Task.course) var tasks: [Task] = []
    @Relationship(inverse: \Event.course) var events: [Event] = []

    init(
        name: String,
        instructor: String? = nil,
        classroom: String? = nil,
        colorHex: String = "#007AFF",
        semester: String? = nil,
        note: String? = nil,
        startDateOverride: Date? = nil,
        endDateOverride: Date? = nil,
        isArchived: Bool = false
    ) {
        id = UUID()
        self.name = name
        self.instructor = instructor
        self.classroom = classroom
        self.colorHex = colorHex
        self.semester = semester
        self.note = note
        self.startDateOverride = startDateOverride
        self.endDateOverride = endDateOverride
        createdAt = .now
        updatedAt = .now
        self.isArchived = isArchived
    }

    var usesSemesterDateRange: Bool {
        startDateOverride == nil && endDateOverride == nil
    }

    func effectiveDateRange(semesterRange: SemesterDateRange) -> SemesterDateRange {
        guard let startDateOverride, let endDateOverride else { return semesterRange }
        return SemesterDateRange(startDate: startDateOverride, endDate: endDateOverride)
    }

    func setDateRange(_ range: SemesterDateRange, usesSemesterRange: Bool) {
        startDateOverride = usesSemesterRange ? nil : range.startDate
        endDateOverride = usesSemesterRange ? nil : range.endDate
        updateSessionDates(to: range)
        updatedAt = .now
    }

    func updateSessionDates(to range: SemesterDateRange) {
        for session in sessions {
            session.startDate = range.startDate
            session.endDate = range.endDate
        }
    }
}
