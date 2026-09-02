import Foundation

enum ScheduleCategory: String {
    case course
    case event
    case task
    case exam

    var label: String {
        switch self {
        case .course: "课程"
        case .event: "日程"
        case .task: "任务"
        case .exam: "考试"
        }
    }

    var symbolName: String {
        switch self {
        case .course: "graduationcap"
        case .event: "calendar.badge.clock"
        case .task: "checkmark.circle"
        case .exam: "pencil.and.list.clipboard"
        }
    }
}

struct ScheduleItem: Identifiable {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date?
    let category: ScheduleCategory
    let colorHex: String?
}

struct TodayOverview {
    let courseCount: Int
    let taskCount: Int
    let eventCount: Int
    let completionRate: Double
}

/// A display-only record for a single habit on one natural day. The durable
/// source remains HabitRecord; this type exists solely to give Calendar and
/// Journal the same, date-based presentation data.
struct DailyHabitStatus: Identifiable {
    let habit: Habit
    let isCompleted: Bool

    var id: UUID { habit.id }
}

/// Shared daily context for Calendar and Journal. It intentionally combines
/// existing models at read time rather than introducing another persistent
/// "daily summary" table that could drift away from tasks, habits or journals.
struct DailyLifeOverview {
    let date: Date
    let scheduleItems: [ScheduleItem]
    let dailyTasks: [Task]
    let completedTasks: [Task]
    let habitStatuses: [DailyHabitStatus]
    let journalEntry: JournalEntry?

    var hasJournal: Bool { journalEntry != nil }
    var completedHabitCount: Int { habitStatuses.filter(\.isCompleted).count }
    var totalHabitCount: Int { habitStatuses.count }
    var taskCompletionRate: Double {
        guard !dailyTasks.isEmpty else { return 0 }
        return Double(completedTasks.count) / Double(dailyTasks.count)
    }

    var journalPreview: String? {
        [journalEntry?.quote, journalEntry?.content]
            .compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .first
    }

    var habitTooltip: String {
        guard !habitStatuses.isEmpty else { return "当天没有习惯记录" }
        let details = habitStatuses.map { "\($0.habit.name)：\($0.isCompleted ? "已完成" : "未完成")" }
        return "习惯 \(completedHabitCount) / \(totalHabitCount) 完成\n" + details.joined(separator: "\n")
    }
}

/// Stores only the presentation choice for the shared daily habit list.
/// Habit and HabitRecord remain the durable sources of habit data; Calendar
/// and Journal both consume this lightweight local preference.
enum HabitDisplayConfiguration {
    static let storageKey = "visibleHabitIDs"
    private static let emptySelectionMarker = "none"

    /// No saved selection means all habits remain visible. This preserves the
    /// behaviour of earlier app versions and existing imported data.
    static func visibleHabits(from habits: [Habit], selection: String) -> [Habit] {
        guard !selection.isEmpty else { return habits }
        let visibleIDs = selectedIDs(from: selection)
        return habits.filter { visibleIDs.contains($0.id) }
    }

    static func isVisible(_ habit: Habit, selection: String) -> Bool {
        selection.isEmpty || selectedIDs(from: selection).contains(habit.id)
    }

    static func updating(
        selection: String,
        habit: Habit,
        isVisible: Bool,
        among habits: [Habit]
    ) -> String {
        var visibleIDs = selection.isEmpty ? Set(habits.map(\.id)) : selectedIDs(from: selection)
        if isVisible {
            visibleIDs.insert(habit.id)
        } else {
            visibleIDs.remove(habit.id)
        }
        return encoded(visibleIDs)
    }

    private static func selectedIDs(from selection: String) -> Set<UUID> {
        guard selection != emptySelectionMarker else { return [] }
        return Set(selection.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    private static func encoded(_ ids: Set<UUID>) -> String {
        guard !ids.isEmpty else { return emptySelectionMarker }
        return ids.map(\.uuidString).sorted().joined(separator: ",")
    }
}

/// Composes the life-map information used by Calendar and Journal for a date.
/// Keeping the rules here prevents each page from implementing subtly different
/// definitions of "this day's task" or "this day's habit".
enum DailyLifeOverviewService {
    static func overview(
        for date: Date,
        journalEntries: [JournalEntry],
        habits: [Habit],
        courses: [Course],
        events: [Event],
        tasks: [Task],
        exams: [Exam],
        calendar: Calendar = .current
    ) -> DailyLifeOverview {
        let dayTasks = tasks
            .filter { isRelevant($0, on: date, calendar: calendar) }
            .sorted(by: taskOrder)
        let completed = dayTasks.filter { $0.status == .completed }
        let habitStatuses = habits
            .sorted { $0.createdAt < $1.createdAt }
            .map { DailyHabitStatus(habit: $0, isCompleted: HabitService.isCompleted($0, on: date, calendar: calendar)) }

        return DailyLifeOverview(
            date: date,
            scheduleItems: ScheduleAggregationService.items(
                for: date,
                courses: courses,
                events: events,
                tasks: tasks,
                exams: exams,
                calendar: calendar
            ),
            dailyTasks: dayTasks,
            completedTasks: completed,
            habitStatuses: habitStatuses,
            journalEntry: JournalEntryService.entry(on: date, in: journalEntries, calendar: calendar)
        )
    }

    /// A task belongs to a day when it was arranged, due, or completed there.
    /// This is a review-oriented union: a completed task should remain visible
    /// in the day's Journal even if it was completed before its deadline.
    static func isRelevant(_ task: Task, on date: Date, calendar: Calendar = .current) -> Bool {
        [task.startDate, task.plannedDate, task.deadline, task.completedAt]
            .compactMap { $0 }
            .contains { calendar.isDate($0, inSameDayAs: date) }
    }

    private static func taskOrder(_ left: Task, _ right: Task) -> Bool {
        let leftDate = left.startDate ?? left.plannedDate ?? left.deadline ?? left.completedAt ?? .distantFuture
        let rightDate = right.startDate ?? right.plannedDate ?? right.deadline ?? right.completedAt ?? .distantFuture
        if leftDate != rightDate { return leftDate < rightDate }
        return left.title.localizedStandardCompare(right.title) == .orderedAscending
    }
}

/// Date-based read rules for a single habit's history. This keeps the visual
/// history calendar independent from SwiftData storage details and ensures
/// Calendar, Journal and the history sheet all interpret HabitRecord dates in
/// exactly the same local-day boundary.
enum HabitHistoryService {
    /// Returns one normalized local-day value per completion. Legacy duplicate
    /// records on the same day intentionally count only once in a calendar.
    static func completedDays(
        for habit: Habit,
        calendar: Calendar = .current
    ) -> Set<Date> {
        Set(habit.records.map { calendar.startOfDay(for: $0.date) })
    }

    static func isCompleted(
        _ habit: Habit,
        on date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        completedDays(for: habit, calendar: calendar)
            .contains(calendar.startOfDay(for: date))
    }

    static func completionCount(
        for habit: Habit,
        inMonthContaining date: Date,
        calendar: Calendar = .current
    ) -> Int {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return 0 }
        return completedDays(for: habit, calendar: calendar)
            .filter { interval.contains($0) }
            .count
    }

    static func completionCount(
        for habit: Habit,
        inYearContaining date: Date,
        calendar: Calendar = .current
    ) -> Int {
        guard let interval = calendar.dateInterval(of: .year, for: date) else { return 0 }
        return completedDays(for: habit, calendar: calendar)
            .filter { interval.contains($0) }
            .count
    }

    /// A current streak may end today or yesterday. Allowing yesterday avoids
    /// prematurely showing zero before the user has had a chance to complete a
    /// habit later in the current day.
    static func currentStreak(
        for habit: Habit,
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let completed = completedDays(for: habit, calendar: calendar)
        let today = calendar.startOfDay(for: date)
        guard !completed.isEmpty else { return 0 }

        var cursor = today
        if !completed.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  completed.contains(yesterday)
            else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while completed.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }
        return streak
    }

    static func longestStreak(
        for habit: Habit,
        calendar: Calendar = .current
    ) -> Int {
        let days = completedDays(for: habit, calendar: calendar).sorted()
        guard !days.isEmpty else { return 0 }

        var longest = 1
        var current = 1
        for pair in zip(days, days.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: pair.0, to: pair.1).day
            if gap == 1 {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
        }
        return longest
    }
}

/// Aggregates durable models into display-only calendar and Today timeline items.
enum ScheduleAggregationService {
    static func items(
        for date: Date,
        courses: [Course],
        events: [Event],
        tasks: [Task],
        exams: [Exam],
        calendar: Calendar = .current
    ) -> [ScheduleItem] {
        let courseItems = courses.flatMap { course in
            course.sessions.compactMap { session -> ScheduleItem? in
                guard occurs(session, on: date, calendar: calendar) else { return nil }
                let start = time(on: date, minutes: session.startTimeMinutes, calendar: calendar)
                let end = time(on: date, minutes: session.endTimeMinutes, calendar: calendar)
                return ScheduleItem(
                    id: session.id,
                    title: course.name,
                    startDate: start,
                    endDate: end,
                    category: .course,
                    colorHex: course.colorHex
                )
            }
        }

        let eventItems = events.compactMap { event -> ScheduleItem? in
            guard calendar.isDate(event.startDate, inSameDayAs: date) else { return nil }
            return ScheduleItem(
                id: event.id,
                title: event.title,
                startDate: event.startDate,
                endDate: event.endDate,
                category: .event,
                colorHex: nil
            )
        }

        let taskItems = tasks.compactMap { task -> ScheduleItem? in
            guard task.status != .completed,
                  let startDate = task.startDate,
                  calendar.isDate(startDate, inSameDayAs: date)
            else { return nil }
            return ScheduleItem(
                id: task.id,
                title: task.title,
                startDate: startDate,
                endDate: task.endDate,
                category: .task,
                colorHex: nil
            )
        }

        let examItems = exams.compactMap { exam -> ScheduleItem? in
            guard calendar.isDate(exam.startDate, inSameDayAs: date) else { return nil }
            return ScheduleItem(
                id: exam.id,
                title: exam.title,
                startDate: exam.startDate,
                endDate: exam.endDate,
                category: .exam,
                colorHex: nil
            )
        }

        return (courseItems + eventItems + taskItems + examItems)
            .sorted { $0.startDate < $1.startDate }
    }

    static func overview(for date: Date, courses: [Course], events: [Event], tasks: [Task], calendar: Calendar = .current) -> TodayOverview {
        let courseCount = courses.flatMap(\.sessions).filter { occurs($0, on: date, calendar: calendar) }.count
        let eventCount = events.filter { calendar.isDate($0.startDate, inSameDayAs: date) }.count
        let dayTasks = tasks.filter { task in
            guard let plannedDate = task.plannedDate else { return false }
            return calendar.isDate(plannedDate, inSameDayAs: date)
        }
        let completed = dayTasks.filter { $0.status == .completed }.count
        let rate = dayTasks.isEmpty ? 0 : Double(completed) / Double(dayTasks.count)
        return TodayOverview(courseCount: courseCount, taskCount: dayTasks.count, eventCount: eventCount, completionRate: rate)
    }

    /// Keeps an in-progress item visible until it ends, then selects the
    /// next scheduled item for Today’s "接下来" summary.
    static func currentOrNextItem(in items: [ScheduleItem], relativeTo date: Date = .now) -> ScheduleItem? {
        items.first { ($0.endDate ?? $0.startDate) >= date }
    }

    static func upcomingDeadlines(from date: Date, tasks: [Task], days: Int = 7, calendar: Calendar = .current) -> [Task] {
        guard let endDate = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) else { return [] }
        return tasks.filter { task in
            guard task.status != .completed, let deadline = task.deadline else { return false }
            return deadline >= calendar.startOfDay(for: date) && deadline < endDate
        }
        .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
    }

    static func occurs(_ session: CourseSession, on date: Date, calendar: Calendar = .current) -> Bool {
        guard session.recurrenceEnabled,
              calendar.component(.weekday, from: date) == session.weekdayRaw,
              calendar.startOfDay(for: date) >= calendar.startOfDay(for: session.startDate)
        else { return false }
        if let endDate = session.endDate,
           calendar.startOfDay(for: date) > calendar.startOfDay(for: endDate) {
            return false
        }
        return matchesWeekPattern(session.weekPattern, on: date, relativeTo: session.startDate, calendar: calendar)
    }

    /// The calendar week containing the effective date is week one; later weeks begin on Monday.
    static func matchesWeekPattern(_ pattern: WeekPattern, on date: Date, relativeTo startDate: Date, calendar: Calendar) -> Bool {
        guard pattern != .all else { return true }
        let start = calendar.startOfDay(for: startDate)
        let target = calendar.startOfDay(for: date)
        guard target >= start else { return false }
        let firstWeekStart = SemesterDateRange.monday(containing: start, calendar: calendar)
        let days = calendar.dateComponents([.day], from: firstWeekStart, to: target).day ?? 0
        let weekNumber = days / 7 + 1
        return switch pattern {
        case .all: true
        case .odd: weekNumber.isMultiple(of: 2) == false
        case .even: weekNumber.isMultiple(of: 2)
        }
    }

    static func time(on date: Date, minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: max(0, minutes) / 60, minute: max(0, minutes) % 60, second: 0, of: date) ?? date
    }
}
