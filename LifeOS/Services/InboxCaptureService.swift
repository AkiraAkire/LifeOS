import Foundation
import SwiftData

/// Persists a low-friction capture as an Inbox task without assigning a date.
enum InboxCaptureService {
    @discardableResult
    static func capture(title: String, in modelContext: ModelContext) throws -> Task {
        let task = Task(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .inbox
        )
        modelContext.insert(task)
        try modelContext.save()
        return task
    }

    /// Assigns a task to a natural day without adding a separate scheduling field.
    /// A legacy precise time is cleared so Today always has one unambiguous task date.
    static func schedule(_ task: Task, on date: Date, in modelContext: ModelContext, calendar: Calendar = .current) throws {
        task.plannedDate = calendar.startOfDay(for: date)
        task.startDate = nil
        task.status = .active
        task.updatedAt = .now
        try modelContext.save()
    }
}
