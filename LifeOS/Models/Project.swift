import Foundation
import SwiftData

/// A local long-running outcome that groups related tasks without duplicating them.
@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var projectDescription: String?
    var deadline: Date?
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool

    @Relationship(inverse: \Task.project) var tasks: [Task] = []

    init(name: String, projectDescription: String? = nil, deadline: Date? = nil, isArchived: Bool = false) {
        id = UUID()
        self.name = name
        self.projectDescription = projectDescription
        self.deadline = deadline
        createdAt = .now
        updatedAt = .now
        self.isArchived = isArchived
    }

    var completionRate: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(tasks.filter { $0.status == .completed }.count) / Double(tasks.count)
    }
}
