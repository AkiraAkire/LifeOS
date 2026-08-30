import Foundation
import SwiftData

/// A single actionable item. It is the durable source for task lists and future Today aggregation.
@Model
final class Task {
    @Attribute(.unique) var id: UUID
    var title: String
    var taskDescription: String?
    var createdAt: Date
    var updatedAt: Date
    var plannedDate: Date?
    var startDate: Date?
    var endDate: Date?
    var deadline: Date?
    var priorityRaw: String
    var statusRaw: String
    var completedAt: Date?
    var sortOrder: Int

    var course: Course?
    var project: Project?
    var assignment: Assignment?

    var tags: [Tag] = []

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    init(
        title: String,
        taskDescription: String? = nil,
        plannedDate: Date? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        deadline: Date? = nil,
        priority: TaskPriority = .medium,
        status: TaskStatus = .active,
        sortOrder: Int = 0
    ) {
        id = UUID()
        self.title = title
        self.taskDescription = taskDescription
        createdAt = .now
        updatedAt = .now
        self.plannedDate = plannedDate
        self.startDate = startDate
        self.endDate = endDate
        self.deadline = deadline
        priorityRaw = priority.rawValue
        statusRaw = status.rawValue
        completedAt = nil
        self.sortOrder = sortOrder
    }

    func markCompleted(at date: Date = .now) {
        status = .completed
        completedAt = date
        updatedAt = date
    }

    func markActive(at date: Date = .now) {
        status = .active
        completedAt = nil
        updatedAt = date
    }
}

/// A presentation-only section for task lists. It never duplicates Task data.
struct TaskListSection: Identifiable {
    let id: String
    let title: String
    let tasks: [Task]
}

/// Groups the same task source differently for Today and Upcoming views.
enum TaskListGrouping {
    /// A task belongs to a day's task list only when its plan is on that day.
    /// If it also has a precise start time, that time must be on the same day.
    /// This prevents an inspector edit from leaving a future task in “今天”.
    static func isScheduled(_ task: Task, on day: Date, calendar: Calendar = .current) -> Bool {
        guard let plannedDate = task.plannedDate,
              calendar.isDate(plannedDate, inSameDayAs: day)
        else { return false }

        guard let startDate = task.startDate else { return true }
        return calendar.isDate(startDate, inSameDayAs: day)
    }

    static func todaySections(for tasks: [Task]) -> [TaskListSection] {
        let definitions: [(String, (Task) -> Bool)] = [
            ("上午", { task in
                guard let date = task.startDate else { return false }
                return (5..<12).contains(Calendar.current.component(.hour, from: date))
            }),
            ("下午", { task in
                guard let date = task.startDate else { return false }
                return (12..<18).contains(Calendar.current.component(.hour, from: date))
            }),
            ("晚上", { task in
                guard let date = task.startDate else { return false }
                let hour = Calendar.current.component(.hour, from: date)
                return hour >= 18 || hour < 5
            }),
            ("其他任务", { $0.startDate == nil })
        ]

        return definitions.compactMap { title, predicate in
            let grouped = tasks.filter(predicate).sorted(by: taskOrder)
            return grouped.isEmpty ? nil : TaskListSection(id: "today-\(title)", title: title, tasks: grouped)
        }
    }

    static func upcomingSections(for tasks: [Task], now: Date = .now, calendar: Calendar = .current) -> [TaskListSection] {
        let startOfToday = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        let weekBoundary = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? startOfToday
        let nextWeekBoundary = calendar.date(byAdding: .day, value: 14, to: startOfToday) ?? startOfToday

        let definitions: [(String, (Task) -> Bool)] = [
            ("逾期", { task in isOverdue(task, relativeTo: startOfToday, calendar: calendar) }),
            ("今天", { task in referenceDate(for: task).map { calendar.isDate($0, inSameDayAs: startOfToday) } ?? false }),
            ("明天", { task in referenceDate(for: task).map { calendar.isDate($0, inSameDayAs: tomorrow) } ?? false }),
            ("本周", { task in
                guard let date = referenceDate(for: task) else { return false }
                return date >= tomorrow && date < weekBoundary && !calendar.isDate(date, inSameDayAs: tomorrow)
            }),
            ("下周", { task in
                guard let date = referenceDate(for: task) else { return false }
                return date >= weekBoundary && date < nextWeekBoundary
            }),
            ("更晚", { task in referenceDate(for: task).map { $0 >= nextWeekBoundary } ?? false })
        ]

        return definitions.compactMap { title, predicate in
            let grouped = tasks.filter(predicate).sorted(by: taskOrder)
            return grouped.isEmpty ? nil : TaskListSection(id: "upcoming-\(title)", title: title, tasks: grouped)
        }
    }

    /// The date a person has actually arranged to work on the task.
    /// A precise start time must win over a date-only plan and a deadline;
    /// otherwise an Aug 26 task with an Aug 27 deadline would incorrectly
    /// appear under “今天” on Aug 27.
    static func referenceDate(for task: Task) -> Date? {
        task.startDate ?? task.plannedDate ?? task.deadline
    }

    /// An item is overdue once either its arranged work day or its deadline
    /// has passed. This keeps missed scheduled work from silently vanishing.
    static func isOverdue(_ task: Task, relativeTo day: Date, calendar: Calendar = .current) -> Bool {
        let startOfDay = calendar.startOfDay(for: day)
        let scheduledDateHasPassed = referenceDate(for: task).map { $0 < startOfDay } ?? false
        let deadlineHasPassed = task.deadline.map { $0 < startOfDay } ?? false
        return scheduledDateHasPassed || deadlineHasPassed
    }

    private static func taskOrder(_ left: Task, _ right: Task) -> Bool {
        (referenceDate(for: left) ?? .distantFuture) < (referenceDate(for: right) ?? .distantFuture)
    }
}
