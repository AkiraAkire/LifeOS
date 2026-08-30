import Foundation
import SwiftData

/// Imports the bundled, documented data set for repeatable manual testing.
/// The caller must obtain explicit user confirmation before calling replaceExistingData.
enum ManualTestDataService {
    static func replaceExistingData(in modelContext: ModelContext) throws {
        let dataset = try loadDataset()
        try validate(dataset)

        try clearExistingData(in: modelContext, saveImmediately: false)
        var projectsBySourceID: [String: Project] = [:]
        for source in dataset.projects { let project = Project(name: source.name, projectDescription: source.description, deadline: try source.deadline.map(date(from:))); modelContext.insert(project); projectsBySourceID[source.id] = project }
        for source in dataset.habits { let habit = Habit(name: source.name, symbolName: source.symbolName); modelContext.insert(habit); for dateValue in source.records { modelContext.insert(HabitRecord(date: try date(from: dateValue), habit: habit)) } }

        var coursesBySourceID: [String: Course] = [:]
        for source in dataset.courses {
            let course = Course(name: source.name, instructor: source.instructor, classroom: source.classroom, colorHex: source.colorHex, semester: source.semester, note: source.note)
            modelContext.insert(course)
            coursesBySourceID[source.id] = course
        }

        for source in dataset.courseSessions {
            guard let course = coursesBySourceID[source.courseID] else { continue }
            modelContext.insert(CourseSession(
                weekday: Weekday(rawValue: source.weekday) ?? .monday,
                startTimeMinutes: source.startTimeMinutes,
                endTimeMinutes: source.endTimeMinutes,
                startDate: try date(from: source.startDate),
                endDate: try source.endDate.map(date(from:)),
                weekPattern: source.weekPattern.flatMap(WeekPattern.init(rawValue:)) ?? .all,
                course: course
            ))
        }

        for source in dataset.assignments {
            guard let course = coursesBySourceID[source.courseID] else { continue }
            let dueDate = try date(from: source.dueDate)
            let task = Task(title: source.title, taskDescription: source.description, plannedDate: dueDate, deadline: dueDate, priority: .medium, status: .active)
            task.course = course
            let assignment = Assignment(title: source.title, assignmentDescription: source.description, dueDate: dueDate, course: course, linkedTask: task)
            task.assignment = assignment
            modelContext.insert(task)
            modelContext.insert(assignment)
        }

        for source in dataset.exams {
            guard let course = coursesBySourceID[source.courseID] else { continue }
            modelContext.insert(Exam(title: source.title, startDate: try date(from: source.startDate), endDate: try source.endDate.map(date(from:)), examDescription: source.description, location: source.location, course: course))
        }

        for source in dataset.tasks {
            let task = Task(
                title: source.title,
                taskDescription: source.description,
                plannedDate: try source.plannedDate.map(date(from:)),
                startDate: try source.startDate.map(date(from:)),
                deadline: try source.deadline.map(date(from:)),
                priority: TaskPriority(rawValue: source.priority) ?? .medium,
                status: TaskStatus(rawValue: source.status) ?? .active
            )
            task.course = source.courseID.flatMap { coursesBySourceID[$0] }
            task.project = source.projectID.flatMap { projectsBySourceID[$0] }
            if task.status == .completed {
                task.markCompleted(at: try source.completedAt.map(date(from:)) ?? .now)
            }
            modelContext.insert(task)
        }

        for source in dataset.events {
            modelContext.insert(Event(title: source.title, startDate: try date(from: source.startDate), endDate: try source.endDate.map(date(from:)), eventType: EventType(rawValue: source.eventType) ?? .personal, eventDescription: source.description, location: source.location))
        }

        for source in dataset.journalEntries {
            modelContext.insert(JournalEntry(date: try date(from: source.date), mood: source.mood.flatMap(Mood.init(rawValue:)), weather: source.weather.flatMap(WeatherCondition.init(rawValue:)), quote: source.quote, content: source.content, importantEvents: source.importantEvents))
        }

        TimetablePeriodStore.save(dataset.timetablePeriods.map { TimetablePeriod(name: $0.name, startTimeMinutes: $0.startTimeMinutes, endTimeMinutes: $0.endTimeMinutes) })
        try modelContext.save()
    }

    static func clearExistingData(in modelContext: ModelContext, saveImmediately: Bool = true) throws {
        // Delete dependents explicitly first. This also clears any legacy or
        // orphaned objects that are not reachable through a cascade relation.
        try modelContext.fetch(FetchDescriptor<HabitRecord>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<CourseSession>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<Assignment>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<Exam>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<Task>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<Event>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<Project>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<Habit>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<Course>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<JournalEntry>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<Tag>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<AppConfiguration>()).forEach(modelContext.delete)
        if saveImmediately { try modelContext.save() }
    }

    static func loadDataset() throws -> ManualTestDataset {
        guard let url = Bundle.main.url(forResource: "manual-test-dataset", withExtension: "json") else {
            throw ManualTestDataError.resourceNotFound
        }
        return try JSONDecoder().decode(ManualTestDataset.self, from: Data(contentsOf: url))
    }

    private static func validate(_ dataset: ManualTestDataset) throws {
        let periods = dataset.timetablePeriods.map { TimetablePeriod(name: $0.name, startTimeMinutes: $0.startTimeMinutes, endTimeMinutes: $0.endTimeMinutes) }
        guard TimetablePeriod.validationMessage(for: periods) == nil else { throw ManualTestDataError.invalidTimetablePeriods }

        let courseIDs = Set(dataset.courses.map(\.id))
        guard courseIDs.count == dataset.courses.count else { throw ManualTestDataError.duplicateCourseID }
        let referencedIDs = dataset.courseSessions.map(\.courseID) + dataset.assignments.map(\.courseID) + dataset.exams.map(\.courseID) + dataset.tasks.compactMap(\.courseID)
        guard referencedIDs.allSatisfy(courseIDs.contains) else { throw ManualTestDataError.invalidCourseReference }
    }

    private static func date(from value: String) throws -> Date {
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: value) { return date }
        throw ManualTestDataError.invalidDate(value)
    }
}

enum ManualTestDataError: LocalizedError {
    case resourceNotFound
    case invalidTimetablePeriods
    case duplicateCourseID
    case invalidCourseReference
    case invalidDate(String)

    var errorDescription: String? {
        switch self {
        case .resourceNotFound: "找不到内置人工测试数据文件。"
        case .invalidTimetablePeriods: "人工测试数据中的课表节次无效。"
        case .duplicateCourseID: "人工测试数据中存在重复课程标识。"
        case .invalidCourseReference: "人工测试数据包含无法关联的课程。"
        case let .invalidDate(value): "人工测试数据中的日期格式无效：\(value)"
        }
    }
}

struct ManualTestDataset: Decodable {
    let projects: [ManualTestProject]
    let habits: [ManualTestHabit]
    let timetablePeriods: [ManualTestTimetablePeriod]
    let courses: [ManualTestCourse]
    let courseSessions: [ManualTestCourseSession]
    let assignments: [ManualTestAssignment]
    let exams: [ManualTestExam]
    let tasks: [ManualTestTask]
    let events: [ManualTestEvent]
    let journalEntries: [ManualTestJournalEntry]
}

struct ManualTestTimetablePeriod: Decodable { let name: String; let startTimeMinutes: Int; let endTimeMinutes: Int }
struct ManualTestCourse: Decodable { let id: String; let name: String; let instructor: String?; let classroom: String?; let colorHex: String; let semester: String?; let note: String? }
struct ManualTestCourseSession: Decodable { let courseID: String; let weekday: Int; let startTimeMinutes: Int; let endTimeMinutes: Int; let startDate: String; let endDate: String?; let weekPattern: String? }
struct ManualTestAssignment: Decodable { let title: String; let courseID: String; let dueDate: String; let description: String? }
struct ManualTestExam: Decodable { let title: String; let courseID: String; let startDate: String; let endDate: String?; let location: String?; let description: String? }
struct ManualTestTask: Decodable { let title: String; let status: String; let priority: String; let courseID: String?; let projectID: String?; let plannedDate: String?; let startDate: String?; let deadline: String?; let completedAt: String?; let description: String? }
struct ManualTestProject: Decodable { let id: String; let name: String; let description: String?; let deadline: String? }
struct ManualTestHabit: Decodable { let name: String; let symbolName: String; let records: [String] }
struct ManualTestEvent: Decodable { let title: String; let startDate: String; let endDate: String?; let location: String?; let eventType: String; let description: String? }
struct ManualTestJournalEntry: Decodable { let date: String; let mood: String?; let weather: String?; let quote: String?; let content: String?; let importantEvents: String? }
