import Foundation
import SwiftData

/// Owns the portable, local-only backup format for LifeOS. The archive stores
/// user data and the small set of UserDefaults preferences that affect what
/// users see, without depending on the SwiftData store's private file format.
enum LifeOSBackupService {
    static let fileExtension = "lifeosbackup"
    private static let formatVersion = 1
    private static let dailyBackupRetentionCount = 7
    private static let weeklyBackupRetentionCount = 4
    private static let recoveryBackupRetentionCount = 14

    static func createArchive(
        from modelContext: ModelContext,
        preferences: LifeOSBackupPreferences = .current()
    ) throws -> LifeOSBackupArchive {
        let payload = try LifeOSBackupPayload(
            appConfigurations: modelContext.fetch(FetchDescriptor<AppConfiguration>()),
            habits: modelContext.fetch(FetchDescriptor<Habit>()),
            habitRecords: modelContext.fetch(FetchDescriptor<HabitRecord>()),
            projects: modelContext.fetch(FetchDescriptor<Project>()),
            tasks: modelContext.fetch(FetchDescriptor<Task>()),
            events: modelContext.fetch(FetchDescriptor<Event>()),
            courses: modelContext.fetch(FetchDescriptor<Course>()),
            sessions: modelContext.fetch(FetchDescriptor<CourseSession>()),
            assignments: modelContext.fetch(FetchDescriptor<Assignment>()),
            exams: modelContext.fetch(FetchDescriptor<Exam>()),
            journalEntries: modelContext.fetch(FetchDescriptor<JournalEntry>()),
            tags: modelContext.fetch(FetchDescriptor<Tag>())
        )

        return LifeOSBackupArchive(
            metadata: .init(formatVersion: formatVersion, exportedAt: .now, appVersion: appVersion),
            preferences: preferences,
            data: payload
        )
    }

    static func writeBackup(
        from modelContext: ModelContext,
        to url: URL,
        preferences: LifeOSBackupPreferences = .current()
    ) throws {
        let archive = try createArchive(from: modelContext, preferences: preferences)
        try write(archive, to: url)
    }

    /// Updates the single snapshot for a calendar day. It is safe to call this
    /// when the app starts and again when it becomes inactive: the newest
    /// version of today's data simply replaces the earlier daily snapshot.
    @discardableResult
    static func createDailySnapshot(
        from modelContext: ModelContext,
        now: Date = .now,
        automaticBackupDirectory: URL? = nil,
        preferences: LifeOSBackupPreferences = .current()
    ) throws -> URL {
        let archive = try createArchive(from: modelContext, preferences: preferences)
        let url = try dailySnapshotURL(now: now, in: automaticBackupDirectory)
        try write(archive, to: url)
        pruneAutomaticBackups(in: url.deletingLastPathComponent())
        return url
    }

    /// Creates a recovery point immediately before an operation that replaces
    /// local data, such as restoring a backup or loading test data.
    @discardableResult
    static func createRecoveryPoint(
        from modelContext: ModelContext,
        kind: LifeOSAutomaticBackupKind,
        automaticBackupDirectory: URL? = nil,
        preferences: LifeOSBackupPreferences = .current()
    ) throws -> URL {
        precondition(kind != .daily, "Daily snapshots use createDailySnapshot(from:)")
        let archive = try createArchive(from: modelContext, preferences: preferences)
        let url = try recoveryPointURL(kind: kind, in: automaticBackupDirectory)
        try write(archive, to: url)
        pruneAutomaticBackups(in: url.deletingLastPathComponent())
        return url
    }

    /// Returns only the app-private recovery points. External backup files are
    /// deliberately not enumerated, so LifeOS never scans user folders.
    static func automaticBackups(
        limit: Int = 8,
        automaticBackupDirectory: URL? = nil
    ) -> [LifeOSAutomaticBackupInfo] {
        guard limit > 0,
              let directory = try? resolvedAutomaticBackupDirectory(in: automaticBackupDirectory),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.contentModificationDateKey],
                  options: [.skipsHiddenFiles]
              )
        else { return [] }

        return files.compactMap { url in
            guard url.pathExtension == fileExtension,
                  let kind = automaticBackupKind(for: url),
                  let archive = try? loadBackup(from: url)
            else { return nil }
            return LifeOSAutomaticBackupInfo(url: url, kind: kind, archive: archive)
        }
        .sorted { $0.archive.metadata.exportedAt > $1.archive.metadata.exportedAt }
        .prefix(limit)
        .map { $0 }
    }

    static func write(_ archive: LifeOSBackupArchive, to url: URL) throws {
        try validate(archive)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(archive).write(to: url, options: .atomic)
        } catch {
            throw LifeOSBackupError.cannotWrite(error.localizedDescription)
        }
    }

    static func loadBackup(from url: URL) throws -> LifeOSBackupArchive {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let archive = try decoder.decode(LifeOSBackupArchive.self, from: Data(contentsOf: url))
            try validate(archive)
            return archive
        } catch let error as LifeOSBackupError {
            throw error
        } catch {
            throw LifeOSBackupError.cannotRead(error.localizedDescription)
        }
    }

    /// Replaces the local SwiftData content only after the archive has passed
    /// validation and the current state has been written to an automatic
    /// recovery backup. The caller still owns the user-facing confirmation.
    @discardableResult
    static func restore(
        _ archive: LifeOSBackupArchive,
        into modelContext: ModelContext,
        automaticBackupDirectory: URL? = nil
    ) throws -> LifeOSBackupRestoreResult {
        try validate(archive)

        let recoveryURL = try createRecoveryPoint(
            from: modelContext,
            kind: .beforeRestore,
            automaticBackupDirectory: automaticBackupDirectory
        )

        do {
            try ManualTestDataService.clearExistingData(in: modelContext, saveImmediately: false)
            try insert(archive.data, into: modelContext)
            try modelContext.save()
            return LifeOSBackupRestoreResult(
                automaticBackupURL: recoveryURL,
                restoredPreferences: archive.preferences
            )
        } catch {
            modelContext.rollback()
            throw LifeOSBackupError.cannotRestore(error.localizedDescription)
        }
    }

    static func defaultFileName(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "LifeOS-备份-\(formatter.string(from: now)).\(fileExtension)"
    }

    static func validate(_ archive: LifeOSBackupArchive) throws {
        guard archive.metadata.formatVersion == formatVersion else {
            throw LifeOSBackupError.unsupportedFormat(archive.metadata.formatVersion)
        }
        guard archive.preferences.semesterRange.isValid else {
            throw LifeOSBackupError.invalidContent("学期开始日期晚于结束日期。")
        }
        guard TimetablePeriod.validationMessage(for: archive.preferences.timetablePeriods) == nil else {
            throw LifeOSBackupError.invalidContent("课表节次设置无效。")
        }

        let data = archive.data
        try ensureUnique(data.appConfigurations.map(\.id), named: "应用配置")
        try ensureUnique(data.habits.map(\.id), named: "习惯")
        try ensureUnique(data.habitRecords.map(\.id), named: "习惯记录")
        try ensureUnique(data.projects.map(\.id), named: "项目")
        try ensureUnique(data.tasks.map(\.id), named: "任务")
        try ensureUnique(data.events.map(\.id), named: "日程")
        try ensureUnique(data.courses.map(\.id), named: "课程")
        try ensureUnique(data.sessions.map(\.id), named: "课程时间")
        try ensureUnique(data.assignments.map(\.id), named: "作业")
        try ensureUnique(data.exams.map(\.id), named: "考试")
        try ensureUnique(data.journalEntries.map(\.id), named: "日记")
        try ensureUnique(data.tags.map(\.id), named: "标签")
        try ensureUnique(data.tags.map(\.name), named: "标签名称")

        let courseIDs = Set(data.courses.map(\.id))
        let projectIDs = Set(data.projects.map(\.id))
        let taskIDs = Set(data.tasks.map(\.id))
        let habitIDs = Set(data.habits.map(\.id))
        let tagIDs = Set(data.tags.map(\.id))
        let assignmentIDs = Set(data.assignments.map(\.id))

        guard data.sessions.allSatisfy({ $0.courseID.map(courseIDs.contains) ?? true }),
              data.assignments.allSatisfy({ ($0.courseID.map(courseIDs.contains) ?? true) && ($0.linkedTaskID.map(taskIDs.contains) ?? true) }),
              data.exams.allSatisfy({ $0.courseID.map(courseIDs.contains) ?? true }),
              data.events.allSatisfy({ ($0.courseID.map(courseIDs.contains) ?? true) && Set($0.tagIDs).isSubset(of: tagIDs) }),
              data.tasks.allSatisfy({
                  ($0.courseID.map(courseIDs.contains) ?? true)
                      && ($0.projectID.map(projectIDs.contains) ?? true)
                      && ($0.assignmentID.map(assignmentIDs.contains) ?? true)
                      && Set($0.tagIDs).isSubset(of: tagIDs)
              }),
              data.habitRecords.allSatisfy({ $0.habitID.map(habitIDs.contains) ?? true })
        else {
            throw LifeOSBackupError.invalidContent("备份中的关联数据不完整。")
        }

        guard data.sessions.allSatisfy({ $0.startTimeMinutes < $0.endTimeMinutes }) else {
            throw LifeOSBackupError.invalidContent("备份中存在结束时间早于开始时间的课程。")
        }
    }

    private static func insert(_ data: LifeOSBackupPayload, into modelContext: ModelContext) throws {
        var courses: [UUID: Course] = [:]
        for source in data.courses {
            let course = Course(
                name: source.name,
                instructor: source.instructor,
                classroom: source.classroom,
                colorHex: source.colorHex,
                symbolName: source.symbolName ?? CourseIcon.defaultSymbolName,
                semester: source.semester,
                note: source.note,
                startDateOverride: source.startDateOverride,
                endDateOverride: source.endDateOverride,
                isArchived: source.isArchived
            )
            course.id = source.id
            course.createdAt = source.createdAt
            course.updatedAt = source.updatedAt
            modelContext.insert(course)
            courses[source.id] = course
        }

        var projects: [UUID: Project] = [:]
        for source in data.projects {
            let project = Project(name: source.name, projectDescription: source.projectDescription, deadline: source.deadline, isArchived: source.isArchived)
            project.id = source.id
            project.createdAt = source.createdAt
            project.updatedAt = source.updatedAt
            modelContext.insert(project)
            projects[source.id] = project
        }

        var tags: [UUID: Tag] = [:]
        for source in data.tags {
            let tag = Tag(name: source.name, colorHex: source.colorHex)
            tag.id = source.id
            tag.createdAt = source.createdAt
            modelContext.insert(tag)
            tags[source.id] = tag
        }

        var habits: [UUID: Habit] = [:]
        for source in data.habits {
            let habit = Habit(name: source.name, symbolName: source.symbolName)
            habit.id = source.id
            habit.createdAt = source.createdAt
            modelContext.insert(habit)
            habits[source.id] = habit
        }

        var tasks: [UUID: Task] = [:]
        for source in data.tasks {
            let task = Task(
                title: source.title,
                taskDescription: source.taskDescription,
                plannedDate: source.plannedDate,
                startDate: source.startDate,
                endDate: source.endDate,
                deadline: source.deadline,
                priority: TaskPriority(rawValue: source.priorityRaw) ?? .medium,
                status: TaskStatus(rawValue: source.statusRaw) ?? .active,
                sortOrder: source.sortOrder
            )
            task.id = source.id
            task.createdAt = source.createdAt
            task.updatedAt = source.updatedAt
            task.priorityRaw = source.priorityRaw
            task.statusRaw = source.statusRaw
            task.completedAt = source.completedAt
            task.course = source.courseID.flatMap { courses[$0] }
            task.project = source.projectID.flatMap { projects[$0] }
            task.tags = source.tagIDs.compactMap { tags[$0] }
            modelContext.insert(task)
            tasks[source.id] = task
        }

        for source in data.sessions {
            let session = CourseSession(
                weekday: Weekday(rawValue: source.weekdayRaw) ?? .monday,
                startTimeMinutes: source.startTimeMinutes,
                endTimeMinutes: source.endTimeMinutes,
                startDate: source.startDate,
                endDate: source.endDate,
                classroomOverride: source.classroomOverride,
                recurrenceEnabled: source.recurrenceEnabled,
                weekPattern: WeekPattern(rawValue: source.weekPatternRaw ?? "") ?? .all,
                course: source.courseID.flatMap { courses[$0] }
            )
            session.id = source.id
            session.weekdayRaw = source.weekdayRaw
            session.weekPatternRaw = source.weekPatternRaw
            modelContext.insert(session)
        }

        var assignments: [UUID: Assignment] = [:]
        for source in data.assignments {
            let assignment = Assignment(
                title: source.title,
                assignmentDescription: source.assignmentDescription,
                assignedDate: source.assignedDate,
                dueDate: source.dueDate,
                course: source.courseID.flatMap { courses[$0] },
                linkedTask: source.linkedTaskID.flatMap { tasks[$0] }
            )
            assignment.id = source.id
            assignment.createdAt = source.createdAt
            assignment.updatedAt = source.updatedAt
            assignment.isCompleted = source.isCompleted
            modelContext.insert(assignment)
            assignments[source.id] = assignment
            if let linkedTask = source.linkedTaskID.flatMap({ tasks[$0] }) {
                linkedTask.assignment = assignment
            }
        }

        for source in data.tasks {
            guard let assignmentID = source.assignmentID,
                  let task = tasks[source.id],
                  let assignment = assignments[assignmentID]
            else { continue }
            task.assignment = assignment
            if assignment.linkedTask == nil { assignment.linkedTask = task }
        }

        for source in data.events {
            let event = Event(
                title: source.title,
                startDate: source.startDate,
                endDate: source.endDate,
                isAllDay: source.isAllDay,
                eventType: EventType(rawValue: source.eventTypeRaw) ?? .personal,
                eventDescription: source.eventDescription,
                location: source.location
            )
            event.id = source.id
            event.eventTypeRaw = source.eventTypeRaw
            event.createdAt = source.createdAt
            event.updatedAt = source.updatedAt
            event.course = source.courseID.flatMap { courses[$0] }
            event.tags = source.tagIDs.compactMap { tags[$0] }
            modelContext.insert(event)
        }

        for source in data.exams {
            let exam = Exam(
                title: source.title,
                startDate: source.startDate,
                endDate: source.endDate,
                examDescription: source.examDescription,
                location: source.location,
                course: source.courseID.flatMap { courses[$0] }
            )
            exam.id = source.id
            exam.createdAt = source.createdAt
            modelContext.insert(exam)
        }

        for source in data.journalEntries {
            let entry = JournalEntry(
                date: source.date,
                mood: source.moodRaw.flatMap(Mood.init(rawValue:)),
                weather: source.weatherRaw.flatMap(WeatherCondition.init(rawValue:)),
                quote: source.quote,
                content: source.content,
                importantEvents: source.importantEvents
            )
            entry.id = source.id
            entry.moodRaw = source.moodRaw
            entry.weatherRaw = source.weatherRaw
            entry.createdAt = source.createdAt
            entry.updatedAt = source.updatedAt
            modelContext.insert(entry)
        }

        for source in data.habitRecords {
            let record = HabitRecord(date: source.date, habit: source.habitID.flatMap { habits[$0] })
            record.id = source.id
            modelContext.insert(record)
        }

        for source in data.appConfigurations {
            modelContext.insert(AppConfiguration(id: source.id, createdAt: source.createdAt))
        }
    }

    private static func resolvedAutomaticBackupDirectory(in directory: URL?) throws -> URL {
        let baseDirectory: URL
        if let directory {
            baseDirectory = directory
        } else {
            guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw LifeOSBackupError.cannotWrite("无法定位应用支持目录。")
            }
            baseDirectory = applicationSupport
                .appendingPathComponent("LifeOS", isDirectory: true)
                .appendingPathComponent("Backups", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        return baseDirectory
    }

    private static func dailySnapshotURL(now: Date, in directory: URL?) throws -> URL {
        let baseDirectory = try resolvedAutomaticBackupDirectory(in: directory)
        return baseDirectory.appendingPathComponent("自动-日常-\(dayFileComponent(for: now)).\(fileExtension)")
    }

    private static func recoveryPointURL(kind: LifeOSAutomaticBackupKind, in directory: URL?) throws -> URL {
        let baseDirectory = try resolvedAutomaticBackupDirectory(in: directory)
        let timestamp = timestampFileComponent(for: .now)
        var url = baseDirectory.appendingPathComponent("自动-\(kind.fileComponent)-\(timestamp).\(fileExtension)")
        var duplicateIndex = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = baseDirectory.appendingPathComponent("自动-\(kind.fileComponent)-\(timestamp)-\(duplicateIndex).\(fileExtension)")
            duplicateIndex += 1
        }
        return url
    }

    private static func automaticBackupKind(for url: URL) -> LifeOSAutomaticBackupKind? {
        let name = url.lastPathComponent
        if name.hasPrefix("自动-日常-") { return .daily }
        if name.hasPrefix("自动-恢复前-") || name.hasPrefix("恢复前-") { return .beforeRestore }
        if name.hasPrefix("自动-导入前-") { return .beforeTestDataImport }
        return nil
    }

    private static func pruneAutomaticBackups(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        else { return }

        let automaticFiles = files.compactMap { url -> (url: URL, kind: LifeOSAutomaticBackupKind, date: Date)? in
            guard url.pathExtension == fileExtension, let kind = automaticBackupKind(for: url) else { return nil }
            let modificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let date = kind == .daily ? dailySnapshotDate(from: url) ?? modificationDate : modificationDate
            return (url, kind, date)
        }

        let dailyFiles = automaticFiles
            .filter { $0.kind == .daily }
            .sorted { $0.date > $1.date }
        var dailyURLsToKeep = Set(dailyFiles.prefix(dailyBackupRetentionCount).map { $0.url })
        var preservedWeeks = Set<String>()
        for file in dailyFiles.dropFirst(dailyBackupRetentionCount) where preservedWeeks.count < weeklyBackupRetentionCount {
            let weekKey = mondayFileComponent(for: file.date)
            if preservedWeeks.insert(weekKey).inserted {
                dailyURLsToKeep.insert(file.url)
            }
        }
        for file in dailyFiles where !dailyURLsToKeep.contains(file.url) {
            try? FileManager.default.removeItem(at: file.url)
        }

        let recoveryFiles = automaticFiles
            .filter { $0.kind != .daily }
            .sorted { $0.date > $1.date }
        for file in recoveryFiles.dropFirst(recoveryBackupRetentionCount) {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    private static func dayFileComponent(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private static func timestampFileComponent(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func dailySnapshotDate(from url: URL) -> Date? {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix("自动-日常-") else { return nil }
        let dateText = String(name.dropFirst("自动-日常-".count))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: dateText)
    }

    private static func mondayFileComponent(for date: Date) -> String {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let monday = SemesterDateRange.monday(containing: date, calendar: calendar)
        return dayFileComponent(for: monday)
    }

    private static func ensureUnique<T: Hashable>(_ values: [T], named name: String) throws {
        guard Set(values).count == values.count else {
            throw LifeOSBackupError.invalidContent("备份中存在重复的\(name)。")
        }
    }

    private static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

/// Distinguishes the automatic copies kept inside LifeOS from a user-exported
/// archive. The labels are user-facing, while filenames remain implementation
/// details within the app's private Application Support directory.
enum LifeOSAutomaticBackupKind: String {
    case daily
    case beforeRestore
    case beforeTestDataImport

    var displayName: String {
        switch self {
        case .daily: "每日自动保护"
        case .beforeRestore: "恢复前保护"
        case .beforeTestDataImport: "导入前保护"
        }
    }

    var symbolName: String {
        switch self {
        case .daily: "clock.arrow.circlepath"
        case .beforeRestore: "arrow.counterclockwise.circle"
        case .beforeTestDataImport: "shield.lefthalf.filled"
        }
    }

    fileprivate var fileComponent: String {
        switch self {
        case .daily: "日常"
        case .beforeRestore: "恢复前"
        case .beforeTestDataImport: "导入前"
        }
    }
}

/// A validated app-private archive ready to show in Settings or restore after
/// the normal destructive-action confirmation.
struct LifeOSAutomaticBackupInfo: Identifiable {
    let url: URL
    let kind: LifeOSAutomaticBackupKind
    let archive: LifeOSBackupArchive

    var id: String { url.path }

    var dateDescription: String {
        archive.metadata.exportedAt.formatted(
            .dateTime.locale(Locale(identifier: "zh_CN")).month().day().hour().minute()
        )
    }
}

struct LifeOSBackupArchive: Codable {
    let metadata: LifeOSBackupMetadata
    let preferences: LifeOSBackupPreferences
    let data: LifeOSBackupPayload

    var summary: String {
        "\(data.courses.count) 门课程、\(data.tasks.count) 个任务、\(data.events.count) 个日程、\(data.journalEntries.count) 篇日记、\(data.habits.count) 个习惯"
    }

    var exportedAtDescription: String {
        metadata.exportedAt.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month().day().hour().minute())
    }
}

struct LifeOSBackupMetadata: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let appVersion: String
}

struct LifeOSBackupRestoreResult {
    let automaticBackupURL: URL
    let restoredPreferences: LifeOSBackupPreferences
}

/// Preferences stored outside SwiftData but needed to recreate the same local
/// experience after a restore.
struct LifeOSBackupPreferences: Codable {
    var launchDestination: String
    var appearance: String
    var weekStartsMonday: Bool
    var use24HourTime: Bool
    var timetablePeriods: [TimetablePeriod]
    var semesterRange: SemesterDateRange
    var visibleHabitSelection: String

    static func current(defaults: UserDefaults = .standard) -> Self {
        Self(
            launchDestination: defaults.string(forKey: "launchDestination") ?? AppDestination.today.rawValue,
            appearance: defaults.string(forKey: "appearance") ?? "system",
            weekStartsMonday: defaults.object(forKey: "weekStartsMonday") as? Bool ?? true,
            use24HourTime: defaults.object(forKey: "use24HourTime") as? Bool ?? true,
            timetablePeriods: TimetablePeriodStore.load(),
            semesterRange: SemesterDateRangeStore.load(),
            visibleHabitSelection: defaults.string(forKey: HabitDisplayConfiguration.storageKey) ?? ""
        )
    }

    func apply(to defaults: UserDefaults = .standard) {
        defaults.set(launchDestination, forKey: "launchDestination")
        defaults.set(appearance, forKey: "appearance")
        defaults.set(weekStartsMonday, forKey: "weekStartsMonday")
        defaults.set(use24HourTime, forKey: "use24HourTime")
        defaults.set(visibleHabitSelection, forKey: HabitDisplayConfiguration.storageKey)
        TimetablePeriodStore.save(timetablePeriods)
        SemesterDateRangeStore.save(semesterRange)
    }
}

struct LifeOSBackupPayload: Codable {
    let appConfigurations: [BackupAppConfiguration]
    let habits: [BackupHabit]
    let habitRecords: [BackupHabitRecord]
    let projects: [BackupProject]
    let tasks: [BackupTask]
    let events: [BackupEvent]
    let courses: [BackupCourse]
    let sessions: [BackupCourseSession]
    let assignments: [BackupAssignment]
    let exams: [BackupExam]
    let journalEntries: [BackupJournalEntry]
    let tags: [BackupTag]

    init(
        appConfigurations: [BackupAppConfiguration], habits: [BackupHabit], habitRecords: [BackupHabitRecord],
        projects: [BackupProject], tasks: [BackupTask], events: [BackupEvent], courses: [BackupCourse],
        sessions: [BackupCourseSession], assignments: [BackupAssignment], exams: [BackupExam],
        journalEntries: [BackupJournalEntry], tags: [BackupTag]
    ) {
        self.appConfigurations = appConfigurations
        self.habits = habits
        self.habitRecords = habitRecords
        self.projects = projects
        self.tasks = tasks
        self.events = events
        self.courses = courses
        self.sessions = sessions
        self.assignments = assignments
        self.exams = exams
        self.journalEntries = journalEntries
        self.tags = tags
    }

    init(
        appConfigurations: [AppConfiguration], habits: [Habit], habitRecords: [HabitRecord], projects: [Project],
        tasks: [Task], events: [Event], courses: [Course], sessions: [CourseSession], assignments: [Assignment],
        exams: [Exam], journalEntries: [JournalEntry], tags: [Tag]
    ) {
        self.appConfigurations = appConfigurations.map(BackupAppConfiguration.init).sorted(by: backupIDOrder)
        self.habits = habits.map(BackupHabit.init).sorted(by: backupIDOrder)
        self.habitRecords = habitRecords.map(BackupHabitRecord.init).sorted(by: backupIDOrder)
        self.projects = projects.map(BackupProject.init).sorted(by: backupIDOrder)
        self.tasks = tasks.map(BackupTask.init).sorted(by: backupIDOrder)
        self.events = events.map(BackupEvent.init).sorted(by: backupIDOrder)
        self.courses = courses.map(BackupCourse.init).sorted(by: backupIDOrder)
        self.sessions = sessions.map(BackupCourseSession.init).sorted(by: backupIDOrder)
        self.assignments = assignments.map(BackupAssignment.init).sorted(by: backupIDOrder)
        self.exams = exams.map(BackupExam.init).sorted(by: backupIDOrder)
        self.journalEntries = journalEntries.map(BackupJournalEntry.init).sorted(by: backupIDOrder)
        self.tags = tags.map(BackupTag.init).sorted(by: backupIDOrder)
    }
}

private protocol BackupIdentifiable { var id: UUID { get } }
private func backupIDOrder<T: BackupIdentifiable>(_ lhs: T, _ rhs: T) -> Bool { lhs.id.uuidString < rhs.id.uuidString }

struct BackupAppConfiguration: Codable, BackupIdentifiable { let id: UUID; let createdAt: Date; init(_ value: AppConfiguration) { id = value.id; createdAt = value.createdAt } }
struct BackupHabit: Codable, BackupIdentifiable { let id: UUID; let name: String; let symbolName: String; let createdAt: Date; init(_ value: Habit) { id = value.id; name = value.name; symbolName = value.symbolName; createdAt = value.createdAt } }
struct BackupHabitRecord: Codable, BackupIdentifiable { let id: UUID; let date: Date; let habitID: UUID?; init(_ value: HabitRecord) { id = value.id; date = value.date; habitID = value.habit?.id } }
struct BackupProject: Codable, BackupIdentifiable { let id: UUID; let name: String; let projectDescription: String?; let deadline: Date?; let createdAt: Date; let updatedAt: Date; let isArchived: Bool; init(_ value: Project) { id = value.id; name = value.name; projectDescription = value.projectDescription; deadline = value.deadline; createdAt = value.createdAt; updatedAt = value.updatedAt; isArchived = value.isArchived } }
struct BackupTag: Codable, BackupIdentifiable { let id: UUID; let name: String; let colorHex: String; let createdAt: Date; init(_ value: Tag) { id = value.id; name = value.name; colorHex = value.colorHex; createdAt = value.createdAt } }

struct BackupCourse: Codable, BackupIdentifiable {
    let id: UUID; let name: String; let instructor: String?; let classroom: String?; let colorHex: String; let symbolName: String?; let semester: String?; let note: String?; let startDateOverride: Date?; let endDateOverride: Date?; let createdAt: Date; let updatedAt: Date; let isArchived: Bool
    init(_ value: Course) { id = value.id; name = value.name; instructor = value.instructor; classroom = value.classroom; colorHex = value.colorHex; symbolName = value.symbolName; semester = value.semester; note = value.note; startDateOverride = value.startDateOverride; endDateOverride = value.endDateOverride; createdAt = value.createdAt; updatedAt = value.updatedAt; isArchived = value.isArchived }
}

struct BackupCourseSession: Codable, BackupIdentifiable {
    let id: UUID; let weekdayRaw: Int; let startTimeMinutes: Int; let endTimeMinutes: Int; let startDate: Date; let endDate: Date?; let classroomOverride: String?; let recurrenceEnabled: Bool; let weekPatternRaw: String?; let courseID: UUID?
    init(_ value: CourseSession) { id = value.id; weekdayRaw = value.weekdayRaw; startTimeMinutes = value.startTimeMinutes; endTimeMinutes = value.endTimeMinutes; startDate = value.startDate; endDate = value.endDate; classroomOverride = value.classroomOverride; recurrenceEnabled = value.recurrenceEnabled; weekPatternRaw = value.weekPatternRaw; courseID = value.course?.id }
}

struct BackupTask: Codable, BackupIdentifiable {
    let id: UUID; let title: String; let taskDescription: String?; let createdAt: Date; let updatedAt: Date; let plannedDate: Date?; let startDate: Date?; let endDate: Date?; let deadline: Date?; let priorityRaw: String; let statusRaw: String; let completedAt: Date?; let sortOrder: Int; let courseID: UUID?; let projectID: UUID?; let assignmentID: UUID?; let tagIDs: [UUID]
    init(
        id: UUID, title: String, taskDescription: String?, createdAt: Date, updatedAt: Date,
        plannedDate: Date?, startDate: Date?, endDate: Date?, deadline: Date?, priorityRaw: String,
        statusRaw: String, completedAt: Date?, sortOrder: Int, courseID: UUID?, projectID: UUID?,
        assignmentID: UUID?, tagIDs: [UUID]
    ) {
        self.id = id
        self.title = title
        self.taskDescription = taskDescription
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.plannedDate = plannedDate
        self.startDate = startDate
        self.endDate = endDate
        self.deadline = deadline
        self.priorityRaw = priorityRaw
        self.statusRaw = statusRaw
        self.completedAt = completedAt
        self.sortOrder = sortOrder
        self.courseID = courseID
        self.projectID = projectID
        self.assignmentID = assignmentID
        self.tagIDs = tagIDs
    }
    init(_ value: Task) { id = value.id; title = value.title; taskDescription = value.taskDescription; createdAt = value.createdAt; updatedAt = value.updatedAt; plannedDate = value.plannedDate; startDate = value.startDate; endDate = value.endDate; deadline = value.deadline; priorityRaw = value.priorityRaw; statusRaw = value.statusRaw; completedAt = value.completedAt; sortOrder = value.sortOrder; courseID = value.course?.id; projectID = value.project?.id; assignmentID = value.assignment?.id; tagIDs = value.tags.map(\.id) }
}

struct BackupEvent: Codable, BackupIdentifiable {
    let id: UUID; let title: String; let eventDescription: String?; let startDate: Date; let endDate: Date?; let isAllDay: Bool; let eventTypeRaw: String; let location: String?; let createdAt: Date; let updatedAt: Date; let courseID: UUID?; let tagIDs: [UUID]
    init(_ value: Event) { id = value.id; title = value.title; eventDescription = value.eventDescription; startDate = value.startDate; endDate = value.endDate; isAllDay = value.isAllDay; eventTypeRaw = value.eventTypeRaw; location = value.location; createdAt = value.createdAt; updatedAt = value.updatedAt; courseID = value.course?.id; tagIDs = value.tags.map(\.id) }
}

struct BackupAssignment: Codable, BackupIdentifiable {
    let id: UUID; let title: String; let assignmentDescription: String?; let assignedDate: Date?; let dueDate: Date?; let createdAt: Date; let updatedAt: Date; let isCompleted: Bool; let courseID: UUID?; let linkedTaskID: UUID?
    init(_ value: Assignment) { id = value.id; title = value.title; assignmentDescription = value.assignmentDescription; assignedDate = value.assignedDate; dueDate = value.dueDate; createdAt = value.createdAt; updatedAt = value.updatedAt; isCompleted = value.isCompleted; courseID = value.course?.id; linkedTaskID = value.linkedTask?.id }
}

struct BackupExam: Codable, BackupIdentifiable {
    let id: UUID; let title: String; let examDescription: String?; let startDate: Date; let endDate: Date?; let location: String?; let createdAt: Date; let courseID: UUID?
    init(_ value: Exam) { id = value.id; title = value.title; examDescription = value.examDescription; startDate = value.startDate; endDate = value.endDate; location = value.location; createdAt = value.createdAt; courseID = value.course?.id }
}

struct BackupJournalEntry: Codable, BackupIdentifiable {
    let id: UUID; let date: Date; let moodRaw: String?; let weatherRaw: String?; let quote: String?; let content: String?; let importantEvents: String?; let createdAt: Date; let updatedAt: Date
    init(_ value: JournalEntry) { id = value.id; date = value.date; moodRaw = value.moodRaw; weatherRaw = value.weatherRaw; quote = value.quote; content = value.content; importantEvents = value.importantEvents; createdAt = value.createdAt; updatedAt = value.updatedAt }
}

enum LifeOSBackupError: LocalizedError {
    case unsupportedFormat(Int)
    case invalidContent(String)
    case cannotRead(String)
    case cannotWrite(String)
    case cannotRestore(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(version): "该备份格式（版本 \(version)）暂不受支持。"
        case let .invalidContent(message): "备份校验未通过：\(message)"
        case let .cannotRead(message): "无法读取备份文件：\(message)"
        case let .cannotWrite(message): "无法写入备份文件：\(message)"
        case let .cannotRestore(message): "恢复备份失败：\(message)"
        }
    }
}
