import Foundation
import SwiftData

/// Stores either a preset SF Symbol name or a short user-defined text / emoji
/// token. Keeping both forms in one portable string avoids a second display-only
/// field while allowing course cards to remain personally recognizable.
enum CourseIcon {
    static let defaultSymbolName = "graduationcap"
    private static let customPrefix = "text:"

    static func customIdentifier(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return customPrefix + String(trimmed.prefix(4))
    }

    static func customText(from identifier: String) -> String? {
        guard identifier.hasPrefix(customPrefix) else { return nil }
        let value = String(identifier.dropFirst(customPrefix.count))
        return value.isEmpty ? nil : value
    }

    static func systemSymbolName(from identifier: String) -> String {
        customText(from: identifier) == nil && !identifier.isEmpty ? identifier : defaultSymbolName
    }
}

/// A course is the information center for recurring sessions, assignments, exams, and related tasks.
@Model
final class Course {
    @Attribute(.unique) var id: UUID
    var name: String
    var instructor: String?
    var classroom: String?
    var colorHex: String
    var symbolName: String = CourseIcon.defaultSymbolName
    var iconImageData: Data?
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
        colorHex: String = "#6E889A",
        symbolName: String = CourseIcon.defaultSymbolName,
        iconImageData: Data? = nil,
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
        self.symbolName = symbolName
        self.iconImageData = iconImageData
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
