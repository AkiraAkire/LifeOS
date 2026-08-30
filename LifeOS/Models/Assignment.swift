import Foundation
import SwiftData

/// Course-specific work. Its actionable state is represented by an optional linked Task.
@Model
final class Assignment {
    @Attribute(.unique) var id: UUID
    var title: String
    var assignmentDescription: String?
    var assignedDate: Date?
    var dueDate: Date?
    var createdAt: Date
    var updatedAt: Date
    var isCompleted: Bool

    var course: Course?
    var linkedTask: Task?

    init(
        title: String,
        assignmentDescription: String? = nil,
        assignedDate: Date? = nil,
        dueDate: Date? = nil,
        course: Course? = nil,
        linkedTask: Task? = nil
    ) {
        id = UUID()
        self.title = title
        self.assignmentDescription = assignmentDescription
        self.assignedDate = assignedDate
        self.dueDate = dueDate
        createdAt = .now
        updatedAt = .now
        isCompleted = false
        self.course = course
        self.linkedTask = linkedTask
    }
}
