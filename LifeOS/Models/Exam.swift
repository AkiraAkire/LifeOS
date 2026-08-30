import Foundation
import SwiftData

/// A scheduled assessment belonging to a course and shown by future calendar aggregation.
@Model
final class Exam {
    @Attribute(.unique) var id: UUID
    var title: String
    var examDescription: String?
    var startDate: Date
    var endDate: Date?
    var location: String?
    var createdAt: Date

    var course: Course?

    init(
        title: String,
        startDate: Date,
        endDate: Date? = nil,
        examDescription: String? = nil,
        location: String? = nil,
        course: Course? = nil
    ) {
        id = UUID()
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.examDescription = examDescription
        self.location = location
        createdAt = .now
        self.course = course
    }
}
