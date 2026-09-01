import SwiftData
import XCTest
@testable import LifeOS

final class CoreModelTests: XCTestCase {
    func testTaskCompletionUpdatesStateAndTimestamp() {
        let task = Task(title: "完成实验报告", priority: .high)
        let completionDate = Date(timeIntervalSince1970: 1_700_000_000)

        task.markCompleted(at: completionDate)

        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(task.completedAt, completionDate)
        XCTAssertEqual(task.updatedAt, completionDate)
        XCTAssertEqual(task.priority, .high)
    }

    func testInboxCaptureCreatesUnscheduledInboxTask() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let task = try InboxCaptureService.capture(title: "  查找新论文  ", in: context)

        XCTAssertEqual(task.title, "查找新论文")
        XCTAssertEqual(task.status, .inbox)
        XCTAssertNil(task.plannedDate)
        XCTAssertNil(task.deadline)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Task>()).count, 1)
    }

    func testSchedulingTaskForTodayPreservesDeadlineAndClearsPreciseTime() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 16))!
        let task = try InboxCaptureService.capture(title: "预约图书馆", in: context)
        task.startDate = calendar.date(byAdding: .day, value: -1, to: date)
        task.deadline = calendar.date(byAdding: .day, value: 2, to: date)

        try InboxCaptureService.schedule(task, on: date, in: context, calendar: calendar)

        XCTAssertEqual(task.status, .active)
        XCTAssertEqual(task.plannedDate, calendar.startOfDay(for: date))
        XCTAssertNil(task.startDate)
        XCTAssertEqual(task.deadline, calendar.date(byAdding: .day, value: 2, to: date))
        XCTAssertTrue(TaskListGrouping.isScheduled(task, on: date, calendar: calendar))
    }

    func testCourseRelationshipsPersistInMemory() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let course = Course(name: "材料热力学")
        let session = CourseSession(
            weekday: .tuesday,
            startTimeMinutes: 600,
            endTimeMinutes: 710,
            startDate: .now,
            course: course
        )
        let assignment = Assignment(title: "实验报告", dueDate: .now, course: course)
        let exam = Exam(title: "期中考试", startDate: .now, course: course)

        context.insert(course)
        context.insert(session)
        context.insert(assignment)
        context.insert(exam)
        try context.save()

        let storedCourses = try context.fetch(FetchDescriptor<Course>())
        let storedCourse = try XCTUnwrap(storedCourses.first)

        XCTAssertEqual(storedCourse.sessions.count, 1)
        XCTAssertEqual(storedCourse.assignments.count, 1)
        XCTAssertEqual(storedCourse.exams.count, 1)
        XCTAssertEqual(storedCourse.sessions.first?.weekday, .tuesday)
    }

    func testProjectKeepsLinkedTasksAndCompletionProgress() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "实验报告")
        let openTask = Task(title: "整理数据")
        let completedTask = Task(title: "完成初稿")
        completedTask.markCompleted()
        openTask.project = project
        completedTask.project = project
        context.insert(project)
        context.insert(openTask)
        context.insert(completedTask)
        try context.save()

        XCTAssertEqual(project.tasks.count, 2)
        XCTAssertEqual(project.completionRate, 0.5)
    }

    func testTagRelationshipIsBidirectional() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let task = Task(title: "阅读论文")
        let tag = Tag(name: "学习")

        task.tags.append(tag)
        context.insert(task)
        context.insert(tag)
        try context.save()

        XCTAssertEqual(task.tags.first?.name, "学习")
        XCTAssertEqual(tag.tasks.first?.title, "阅读论文")
    }

    func testHabitDisplayConfigurationKeepsOneSharedVisibleSet() {
        let reading = Habit(name: "阅读", symbolName: "book.closed")
        let exercise = Habit(name: "运动", symbolName: "figure.run")
        let habits = [reading, exercise]

        XCTAssertEqual(
            HabitDisplayConfiguration.visibleHabits(from: habits, selection: "").map(\.id),
            [reading.id, exercise.id]
        )

        let onlyReading = HabitDisplayConfiguration.updating(
            selection: "",
            habit: exercise,
            isVisible: false,
            among: habits
        )
        XCTAssertEqual(
            HabitDisplayConfiguration.visibleHabits(from: habits, selection: onlyReading).map(\.id),
            [reading.id]
        )

        let noneVisible = HabitDisplayConfiguration.updating(
            selection: onlyReading,
            habit: reading,
            isVisible: false,
            among: habits
        )
        XCTAssertTrue(HabitDisplayConfiguration.visibleHabits(from: habits, selection: noneVisible).isEmpty)

        let exerciseRestored = HabitDisplayConfiguration.updating(
            selection: noneVisible,
            habit: exercise,
            isVisible: true,
            among: habits
        )
        XCTAssertEqual(
            HabitDisplayConfiguration.visibleHabits(from: habits, selection: exerciseRestored).map(\.id),
            [exercise.id]
        )
    }

    func testHabitHistoryNormalizesCompletionDaysAndCalculatesStreaks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func day(_ value: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 8, day: value, hour: 15))!
        }

        let reading = Habit(name: "阅读", symbolName: "book.closed")
        // Duplicate and non-midnight records must still render as one completed
        // calendar day, preserving the user-facing natural-day semantics.
        [1, 3, 27, 28, 28, 29].forEach { reading.records.append(HabitRecord(date: day($0))) }

        XCTAssertTrue(HabitHistoryService.isCompleted(reading, on: day(28), calendar: calendar))
        XCTAssertFalse(HabitHistoryService.isCompleted(reading, on: day(30), calendar: calendar))
        XCTAssertEqual(HabitHistoryService.completionCount(for: reading, inMonthContaining: day(1), calendar: calendar), 5)
        XCTAssertEqual(HabitHistoryService.completionCount(for: reading, inYearContaining: day(1), calendar: calendar), 5)
        XCTAssertEqual(HabitHistoryService.currentStreak(for: reading, on: day(30), calendar: calendar), 3)
        XCTAssertEqual(HabitHistoryService.longestStreak(for: reading, calendar: calendar), 3)
    }

    func testScheduleAggregationIncludesAllSourcesInTimeOrder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 1_728_000_000)
        let weekday = Weekday(rawValue: calendar.component(.weekday, from: day))!
        let course = Course(name: "材料物理")
        let session = CourseSession(
            weekday: weekday,
            startTimeMinutes: 9 * 60,
            endTimeMinutes: 10 * 60 + 50,
            startDate: day
        )
        course.sessions.append(session)

        let event = Event(title: "组会", startDate: ScheduleAggregationService.time(on: day, minutes: 14 * 60, calendar: calendar))
        let task = Task(title: "完成报告", startDate: ScheduleAggregationService.time(on: day, minutes: 11 * 60, calendar: calendar))
        let exam = Exam(title: "测验", startDate: ScheduleAggregationService.time(on: day, minutes: 16 * 60, calendar: calendar))

        let items = ScheduleAggregationService.items(
            for: day,
            courses: [course],
            events: [event],
            tasks: [task],
            exams: [exam],
            calendar: calendar
        )

        XCTAssertEqual(items.map(\.title), ["材料物理", "完成报告", "组会", "测验"])
        XCTAssertEqual(items.map(\.category), [.course, .task, .event, .exam])
    }

    func testCourseSessionWeekPatternsAlternateFromEffectiveWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstMonday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!
        let secondMonday = calendar.date(byAdding: .day, value: 7, to: firstMonday)!
        let oddSession = CourseSession(
            weekday: .monday,
            startTimeMinutes: 9 * 60,
            endTimeMinutes: 10 * 60,
            startDate: firstMonday,
            weekPattern: .odd
        )
        let evenSession = CourseSession(
            weekday: .monday,
            startTimeMinutes: 9 * 60,
            endTimeMinutes: 10 * 60,
            startDate: firstMonday,
            weekPattern: .even
        )

        XCTAssertTrue(ScheduleAggregationService.occurs(oddSession, on: firstMonday, calendar: calendar))
        XCTAssertFalse(ScheduleAggregationService.occurs(evenSession, on: firstMonday, calendar: calendar))
        XCTAssertFalse(ScheduleAggregationService.occurs(oddSession, on: secondMonday, calendar: calendar))
        XCTAssertTrue(ScheduleAggregationService.occurs(evenSession, on: secondMonday, calendar: calendar))
    }

    func testSemesterDateRangeUsesContainingWeekThenMondayBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 12, day: 30))!
        let range = SemesterDateRange(startDate: start, endDate: end, calendar: calendar)
        let containingMonday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!
        let containingSunday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
        let nextMonday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31))!

        XCTAssertEqual(range.weekNumber(containing: start, calendar: calendar), 1)
        XCTAssertEqual(range.weekNumber(containing: containingMonday, calendar: calendar), 1)
        XCTAssertEqual(range.weekNumber(containing: containingSunday, calendar: calendar), 1)
        XCTAssertEqual(range.weekNumber(containing: nextMonday, calendar: calendar), 2)
        XCTAssertEqual(TimetableWeekFilter.preferred(for: start, semesterRange: range, calendar: calendar), .odd)
        XCTAssertEqual(TimetableWeekFilter.preferred(for: nextMonday, semesterRange: range, calendar: calendar), .even)
        XCTAssertTrue(ScheduleAggregationService.matchesWeekPattern(.odd, on: start, relativeTo: start, calendar: calendar))
        XCTAssertTrue(ScheduleAggregationService.matchesWeekPattern(.even, on: nextMonday, relativeTo: start, calendar: calendar))
    }

    func testSemesterWeekCountSetsEndDateToFinalSunday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26))!
        let expectedEnd = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let end = SemesterDateRange.endDate(forWeekCount: 4, startDate: start, calendar: calendar)
        let range = SemesterDateRange(startDate: start, endDate: end, calendar: calendar)

        XCTAssertEqual(end, expectedEnd)
        XCTAssertEqual(range.weekCount(calendar: calendar), 4)
    }

    func testGlobalSemesterDatesPreserveCourseSpecificOverride() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let oldRange = SemesterDateRange(
            startDate: calendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!,
            endDate: calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!,
            calendar: calendar
        )
        let newRange = SemesterDateRange(
            startDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!,
            endDate: calendar.date(from: DateComponents(year: 2027, month: 1, day: 15))!,
            calendar: calendar
        )
        let customRange = SemesterDateRange(
            startDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 8))!,
            endDate: calendar.date(from: DateComponents(year: 2026, month: 11, day: 30))!,
            calendar: calendar
        )

        let inheritedCourse = Course(name: "跟随学期课程")
        let inheritedSession = CourseSession(weekday: .monday, startTimeMinutes: 480, endTimeMinutes: 525, startDate: oldRange.startDate)
        inheritedCourse.sessions.append(inheritedSession)
        inheritedCourse.setDateRange(oldRange, usesSemesterRange: true)

        let customCourse = Course(name: "独立日期课程")
        let customSession = CourseSession(weekday: .tuesday, startTimeMinutes: 480, endTimeMinutes: 525, startDate: customRange.startDate)
        customCourse.sessions.append(customSession)
        customCourse.setDateRange(customRange, usesSemesterRange: false)

        SemesterDateRangeCoordinator.applyGlobalRange(newRange, to: [inheritedCourse, customCourse])

        XCTAssertEqual(inheritedSession.startDate, newRange.startDate)
        XCTAssertEqual(inheritedSession.endDate, newRange.endDate)
        XCTAssertEqual(customSession.startDate, customRange.startDate)
        XCTAssertEqual(customSession.endDate, customRange.endDate)
        XCTAssertTrue(inheritedCourse.usesSemesterDateRange)
        XCTAssertFalse(customCourse.usesSemesterDateRange)
    }

    func testCourseSessionCanEditAnExistingWeekRule() {
        let firstMonday = Date(timeIntervalSince1970: 1_724_659_200)
        let session = CourseSession(
            weekday: .monday,
            startTimeMinutes: 9 * 60,
            endTimeMinutes: 10 * 60,
            startDate: firstMonday
        )
        let originalID = session.id

        session.weekday = .wednesday
        session.startTimeMinutes = 10 * 60
        session.endTimeMinutes = 11 * 60
        session.weekPattern = .even

        XCTAssertEqual(session.id, originalID)
        XCTAssertEqual(session.weekday, .wednesday)
        XCTAssertEqual(session.startTimeMinutes, 10 * 60)
        XCTAssertEqual(session.endTimeMinutes, 11 * 60)
        XCTAssertEqual(session.weekPattern, .even)
    }

    func testDeletingOneCourseSessionPreservesTheCourseAndOtherSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let course = Course(name: "工程电路与电子基础")
        let tuesday = CourseSession(
            weekday: .tuesday,
            startTimeMinutes: 10 * 60 + 10,
            endTimeMinutes: 11 * 60 + 50,
            startDate: .now,
            course: course
        )
        let thursday = CourseSession(
            weekday: .thursday,
            startTimeMinutes: 10 * 60 + 10,
            endTimeMinutes: 11 * 60 + 50,
            startDate: .now,
            course: course
        )
        context.insert(course)
        context.insert(tuesday)
        context.insert(thursday)
        try context.save()

        context.delete(tuesday)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Course>()).count, 1)
        let remainingSessions = try context.fetch(FetchDescriptor<CourseSession>())
        XCTAssertEqual(remainingSessions.count, 1)
        XCTAssertEqual(remainingSessions.first?.id, thursday.id)
    }

    func testCourseSessionsSortMondayFirstThenByStartTime() {
        let sunday = CourseSession(
            weekday: .sunday,
            startTimeMinutes: 8 * 60,
            endTimeMinutes: 9 * 60,
            startDate: .now
        )
        let mondayAfternoon = CourseSession(
            weekday: .monday,
            startTimeMinutes: 14 * 60,
            endTimeMinutes: 15 * 60,
            startDate: .now
        )
        let thursday = CourseSession(
            weekday: .thursday,
            startTimeMinutes: 10 * 60,
            endTimeMinutes: 11 * 60,
            startDate: .now
        )
        let mondayMorning = CourseSession(
            weekday: .monday,
            startTimeMinutes: 8 * 60,
            endTimeMinutes: 9 * 60,
            startDate: .now
        )

        let sorted = CourseSessionOrdering.sorted([
            sunday,
            mondayAfternoon,
            thursday,
            mondayMorning
        ])

        XCTAssertEqual(sorted.map(\.id), [
            mondayMorning.id,
            mondayAfternoon.id,
            thursday.id,
            sunday.id
        ])
    }

    func testTimetablePeriodValidationRejectsInvalidRangesAndOverlaps() {
        let first = TimetablePeriod(name: "第 1 节", startTimeMinutes: 8 * 60, endTimeMinutes: 8 * 60 + 45)
        let overlap = TimetablePeriod(name: "第 2 节", startTimeMinutes: 8 * 60 + 30, endTimeMinutes: 9 * 60 + 15)
        let invalid = TimetablePeriod(name: "第 3 节", startTimeMinutes: 10 * 60, endTimeMinutes: 10 * 60)

        XCTAssertNil(TimetablePeriod.validationMessage(for: [first]))
        XCTAssertNotNil(TimetablePeriod.validationMessage(for: [first, overlap]))
        XCTAssertNotNil(TimetablePeriod.validationMessage(for: [invalid]))
    }

    func testTimetableLayoutSpansEveryTouchedPeriod() {
        let periods = TimetablePeriod.defaultPeriods

        let twoPeriodSpan = TimetableLayout.periodSpan(
            startTimeMinutes: 10 * 60 + 10,
            endTimeMinutes: 11 * 60 + 50,
            periods: periods
        )
        XCTAssertEqual(twoPeriodSpan, TimetablePeriodSpan(startIndex: 2, endIndex: 3))
        XCTAssertEqual(twoPeriodSpan?.rowCount, 2)

        let longSpan = TimetableLayout.periodSpan(
            startTimeMinutes: 8 * 60,
            endTimeMinutes: 17 * 60 + 50,
            periods: periods
        )
        XCTAssertEqual(longSpan, TimetablePeriodSpan(startIndex: 0, endIndex: 7))
        XCTAssertEqual(longSpan?.rowCount, 8)
    }

    func testTimetableLayoutPlacesOverlappingSessionsInParallelLanes() {
        let firstID = UUID()
        let secondID = UUID()
        let laterID = UUID()
        let otherDayID = UUID()

        let placements = TimetableLayout.lanePlacements(for: [
            TimetablePlacementInput(id: firstID, dayIndex: 1, startIndex: 2, endIndex: 3),
            TimetablePlacementInput(id: secondID, dayIndex: 1, startIndex: 2, endIndex: 3),
            TimetablePlacementInput(id: laterID, dayIndex: 1, startIndex: 4, endIndex: 4),
            TimetablePlacementInput(id: otherDayID, dayIndex: 2, startIndex: 2, endIndex: 3)
        ])

        XCTAssertEqual(placements[firstID]?.laneCount, 2)
        XCTAssertEqual(placements[secondID]?.laneCount, 2)
        XCTAssertEqual(
            Set([placements[firstID]?.laneIndex, placements[secondID]?.laneIndex].compactMap { $0 }),
            Set([0, 1])
        )
        XCTAssertEqual(placements[laterID], TimetableLanePlacement(laneIndex: 0, laneCount: 1))
        XCTAssertEqual(placements[otherDayID], TimetableLanePlacement(laneIndex: 0, laneCount: 1))
    }

    func testJournalEntryServiceReusesEntryForSameNaturalDay() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let date = Date(timeIntervalSince1970: 1_728_000_000)
        let entry = JournalEntry(date: date, content: "初稿")
        context.insert(entry)
        try context.save()

        let resolved = JournalEntryService.entry(on: date, in: [entry])
        let saved = JournalEntryService.save(
            entry: resolved,
            date: date,
            mood: .good,
            weather: .sunny,
            quote: "今天不错",
            content: "更新后的正文",
            importantEvents: nil,
            in: context
        )

        XCTAssertTrue(saved === entry)
        XCTAssertEqual(saved.mood, .good)
        XCTAssertEqual(saved.weather, .sunny)
        XCTAssertEqual(saved.content, "更新后的正文")
        XCTAssertEqual(try context.fetch(FetchDescriptor<JournalEntry>()).count, 1)
    }

    func testCalendarJournalEntryEnsureReusesNaturalDayEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 15))!
        let existing = JournalEntry(date: calendar.startOfDay(for: date), content: "已有记录")
        context.insert(existing)
        try context.save()

        let reused = JournalEntryService.ensureEntry(for: date, in: [existing], modelContext: context, calendar: calendar)
        let anotherDay = calendar.date(byAdding: .day, value: 1, to: date)!
        let created = JournalEntryService.ensureEntry(for: anotherDay, in: [existing], modelContext: context, calendar: calendar)

        XCTAssertTrue(reused === existing)
        XCTAssertFalse(created === existing)
        XCTAssertEqual(try context.fetch(FetchDescriptor<JournalEntry>()).count, 2)
        XCTAssertTrue(calendar.isDate(created.date, inSameDayAs: anotherDay))
    }

    func testJournalMonthCalendarLayoutBuildsSixWeeksFromTheConfiguredWeekStart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let august = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!
        let expectedFirstDay = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        let expectedLastDay = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6))!

        let days = JournalMonthCalendarLayout.visibleDays(for: august, calendar: calendar)

        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.first, expectedFirstDay)
        XCTAssertEqual(days.last, expectedLastDay)
        XCTAssertEqual(JournalMonthCalendarLayout.weekdaySymbols(calendar: calendar), ["一", "二", "三", "四", "五", "六", "日"])
    }

    func testDailyLifeOverviewCombinesJournalHabitsTasksAndSchedule() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 12))!
        let weekday = Weekday(rawValue: calendar.component(.weekday, from: date))!

        let course = Course(name: "材料物理")
        course.sessions.append(CourseSession(
            weekday: weekday,
            startTimeMinutes: 9 * 60,
            endTimeMinutes: 10 * 60,
            startDate: date
        ))

        let reading = Habit(name: "阅读", symbolName: "book")
        let exercise = Habit(name: "运动", symbolName: "figure.run")
        reading.records.append(HabitRecord(date: date))

        let planned = Task(title: "整理笔记", plannedDate: date)
        let completed = Task(title: "完成报告")
        completed.markCompleted(at: date)
        let due = Task(title: "提交数据", deadline: date)
        let later = Task(title: "下周任务", deadline: calendar.date(byAdding: .day, value: 7, to: date))
        let event = Event(
            title: "课题组组会",
            startDate: ScheduleAggregationService.time(on: date, minutes: 14 * 60, calendar: calendar),
            endDate: ScheduleAggregationService.time(on: date, minutes: 15 * 60, calendar: calendar),
            eventDescription: "讨论实验进展"
        )
        let journal = JournalEntry(date: date, quote: "完成了重要实验")

        let overview = DailyLifeOverviewService.overview(
            for: date,
            journalEntries: [journal],
            habits: [reading, exercise],
            courses: [course],
            events: [event],
            tasks: [planned, completed, due, later],
            exams: [],
            calendar: calendar
        )

        XCTAssertTrue(overview.hasJournal)
        XCTAssertEqual(overview.journalPreview, "完成了重要实验")
        XCTAssertEqual(overview.completedHabitCount, 1)
        XCTAssertEqual(overview.totalHabitCount, 2)
        XCTAssertEqual(Set(overview.dailyTasks.map(\.title)), Set(["整理笔记", "完成报告", "提交数据"]))
        XCTAssertEqual(overview.completedTasks.map(\.title), ["完成报告"])
        XCTAssertEqual(overview.scheduleItems.map(\.title), ["材料物理", "课题组组会"])
    }

    func testQuickWeatherUpdatePreservesExistingJournalContent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let date = Date(timeIntervalSince1970: 1_728_000_000)
        let entry = JournalEntry(date: date, mood: .good, quote: "原句", content: "原正文")
        context.insert(entry)
        try context.save()

        let saved = JournalEntryService.setWeather(.rainy, for: date, in: [entry], modelContext: context)

        XCTAssertTrue(saved === entry)
        XCTAssertEqual(saved.weather, .rainy)
        XCTAssertEqual(saved.mood, .good)
        XCTAssertEqual(saved.quote, "原句")
        XCTAssertEqual(saved.content, "原正文")
        XCTAssertEqual(try context.fetch(FetchDescriptor<JournalEntry>()).count, 1)
    }

    func testJournalEntryServiceDeletesOnlySelectedEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let first = JournalEntry(date: Date(timeIntervalSince1970: 1_728_000_000), content: "要删除")
        let second = JournalEntry(date: Date(timeIntervalSince1970: 1_728_086_400), content: "要保留")
        context.insert(first)
        context.insert(second)
        try context.save()

        try JournalEntryService.delete(first, in: context)

        let remainingEntries = try context.fetch(FetchDescriptor<JournalEntry>())
        XCTAssertEqual(remainingEntries.count, 1)
        XCTAssertEqual(remainingEntries.first?.content, "要保留")
    }

    func testUpcomingTaskGroupingSeparatesOverdueAndTomorrow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_728_000_000)
        let overdue = Task(title: "逾期报告", deadline: calendar.date(byAdding: .day, value: -1, to: now))
        let tomorrow = Task(title: "明天复习", plannedDate: calendar.date(byAdding: .day, value: 1, to: now))

        let sections = TaskListGrouping.upcomingSections(for: [overdue, tomorrow], now: now, calendar: calendar)

        XCTAssertEqual(sections.map(\.title), ["逾期", "明天"])
        XCTAssertEqual(sections.first?.tasks.first?.title, "逾期报告")
        XCTAssertEqual(sections.last?.tasks.first?.title, "明天复习")
    }

    func testUpcomingGroupingUsesScheduledDateBeforeDeadline() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 27, hour: 9))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let scheduledYesterday = Task(
            title: "昨天已安排的邮件",
            plannedDate: yesterday,
            startDate: yesterday,
            deadline: today
        )
        let scheduledTomorrow = Task(
            title: "明天的报告",
            plannedDate: tomorrow,
            deadline: calendar.date(byAdding: .day, value: 3, to: today)
        )

        let sections = TaskListGrouping.upcomingSections(
            for: [scheduledYesterday, scheduledTomorrow],
            now: today,
            calendar: calendar
        )

        XCTAssertEqual(sections.map(\.title), ["逾期", "明天"])
        XCTAssertEqual(sections[0].tasks.first?.title, "昨天已安排的邮件")
        XCTAssertEqual(sections[1].tasks.first?.title, "明天的报告")
    }

    func testTodayTaskRequiresMatchingPlannedAndScheduledDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 9))!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let plannedForToday = Task(title: "今天的无时间任务", plannedDate: today)
        let timedForToday = Task(title: "今天的定时任务", plannedDate: today, startDate: today)
        let mismatchedTask = Task(title: "明天才开始", plannedDate: today, startDate: tomorrow)
        let futureTask = Task(title: "明天任务", plannedDate: tomorrow)

        XCTAssertTrue(TaskListGrouping.isScheduled(plannedForToday, on: today, calendar: calendar))
        XCTAssertTrue(TaskListGrouping.isScheduled(timedForToday, on: today, calendar: calendar))
        XCTAssertFalse(TaskListGrouping.isScheduled(mismatchedTask, on: today, calendar: calendar))
        XCTAssertFalse(TaskListGrouping.isScheduled(futureTask, on: today, calendar: calendar))
    }

    func testManualTestDataClearRemovesPersistedEntities() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(Task(title: "旧任务"))
        context.insert(Event(title: "旧日程", startDate: .now))
        context.insert(Course(name: "旧课程"))
        context.insert(JournalEntry(date: .now, content: "旧日记"))
        context.insert(Tag(name: "旧标签"))
        try context.save()

        try ManualTestDataService.clearExistingData(in: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<Task>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Event>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Course>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<JournalEntry>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Tag>()).isEmpty)
    }

    func testManualTestDataImportReplacesExistingData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(Task(title: "需要被替换的旧任务"))
        try context.save()

        try ManualTestDataService.replaceExistingData(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Course>()).count, 10)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseSession>()).count, 14)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Assignment>()).count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exam>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Task>()).count, 13)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Event>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<JournalEntry>()).count, 3)
    }

    func testCompleteBackupRoundTripsRelationshipsAndPreferences() throws {
        let sourceContainer = try makeContainer()
        let sourceContext = ModelContext(sourceContainer)
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let course = Course(name: "材料物理", instructor: "李老师", classroom: "一教 203", colorHex: "#5E5CE6", semester: "2026 秋季学期")
        let session = CourseSession(
            weekday: .monday,
            startTimeMinutes: 9 * 60,
            endTimeMinutes: 10 * 60 + 50,
            startDate: date,
            endDate: date.addingTimeInterval(7 * 24 * 60 * 60),
            classroomOverride: "一教 203",
            recurrenceEnabled: true,
            weekPattern: .odd,
            course: course
        )
        let project = Project(name: "实验项目", projectDescription: "完成实验报告", deadline: date)
        let tag = Tag(name: "学习", colorHex: "#34C759")
        let task = Task(
            title: "完成实验报告",
            taskDescription: "整理实验数据",
            plannedDate: date,
            startDate: date,
            endDate: date.addingTimeInterval(3_600),
            deadline: date.addingTimeInterval(86_400),
            priority: .high,
            status: .active,
            sortOrder: 2
        )
        task.course = course
        task.project = project
        task.tags = [tag]
        let assignment = Assignment(title: "实验报告", assignmentDescription: "第三次实验", dueDate: task.deadline, course: course, linkedTask: task)
        task.assignment = assignment
        let event = Event(title: "课题组组会", startDate: date, endDate: date.addingTimeInterval(3_600), eventType: .personal, eventDescription: "汇报进度", location: "实验楼")
        event.course = course
        event.tags = [tag]
        let exam = Exam(title: "期中测验", startDate: date, examDescription: "第一章", location: "一教 203", course: course)
        let habit = Habit(name: "阅读", symbolName: "book.closed")
        let habitRecord = HabitRecord(date: date, habit: habit)
        let journal = JournalEntry(date: date, mood: .good, weather: .sunny, quote: "稳步前进", content: "完成了数据整理", importantEvents: "实验报告")
        let configuration = AppConfiguration(createdAt: date)

        sourceContext.insert(course)
        sourceContext.insert(session)
        sourceContext.insert(project)
        sourceContext.insert(tag)
        sourceContext.insert(task)
        sourceContext.insert(assignment)
        sourceContext.insert(event)
        sourceContext.insert(exam)
        sourceContext.insert(habit)
        sourceContext.insert(habitRecord)
        sourceContext.insert(journal)
        sourceContext.insert(configuration)
        try sourceContext.save()

        let preferences = LifeOSBackupPreferences(
            launchDestination: AppDestination.calendar.rawValue,
            appearance: "dark",
            weekStartsMonday: true,
            use24HourTime: true,
            timetablePeriods: [TimetablePeriod(name: "上午第 1 节", startTimeMinutes: 480, endTimeMinutes: 530)],
            semesterRange: SemesterDateRange(startDate: date, endDate: date.addingTimeInterval(14 * 86_400)),
            visibleHabitSelection: habit.id.uuidString
        )
        let archive = try LifeOSBackupService.createArchive(from: sourceContext, preferences: preferences)
        XCTAssertEqual(archive.summary, "1 门课程、1 个任务、1 个日程、1 篇日记、1 个习惯")

        let backupURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("LifeOS-\(UUID().uuidString).lifeosbackup")
        defer { try? FileManager.default.removeItem(at: backupURL) }
        try LifeOSBackupService.write(archive, to: backupURL)
        let loadedArchive = try LifeOSBackupService.loadBackup(from: backupURL)

        let targetContainer = try makeContainer()
        let targetContext = ModelContext(targetContainer)
        targetContext.insert(Task(title: "将被恢复替换的旧任务"))
        try targetContext.save()
        let recoveryDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("LifeOSRecovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: recoveryDirectory) }

        let result = try LifeOSBackupService.restore(loadedArchive, into: targetContext, automaticBackupDirectory: recoveryDirectory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.automaticBackupURL.path))
        XCTAssertEqual(result.restoredPreferences.visibleHabitSelection, habit.id.uuidString)
        XCTAssertEqual(try targetContext.fetch(FetchDescriptor<Course>()).count, 1)
        XCTAssertEqual(try targetContext.fetch(FetchDescriptor<Task>()).count, 1)
        XCTAssertEqual(try targetContext.fetch(FetchDescriptor<Event>()).count, 1)
        XCTAssertEqual(try targetContext.fetch(FetchDescriptor<JournalEntry>()).count, 1)
        XCTAssertEqual(try targetContext.fetch(FetchDescriptor<HabitRecord>()).count, 1)

        let restoredTask = try XCTUnwrap(targetContext.fetch(FetchDescriptor<Task>()).first)
        XCTAssertEqual(restoredTask.id, task.id)
        XCTAssertEqual(restoredTask.course?.name, "材料物理")
        XCTAssertEqual(restoredTask.project?.name, "实验项目")
        XCTAssertEqual(restoredTask.tags.map(\.name), ["学习"])
        XCTAssertEqual(restoredTask.assignment?.title, "实验报告")
        XCTAssertEqual(restoredTask.assignment?.linkedTask?.id, restoredTask.id)
        XCTAssertEqual(restoredTask.priority, .high)
        XCTAssertEqual(restoredTask.sortOrder, 2)

        let restoredEvent = try XCTUnwrap(targetContext.fetch(FetchDescriptor<Event>()).first)
        XCTAssertEqual(restoredEvent.tags.map(\.name), ["学习"])
        XCTAssertEqual(restoredEvent.course?.id, restoredTask.course?.id)
    }

    func testBackupValidationRejectsBrokenReferencesBeforeRestore() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let archive = try LifeOSBackupService.createArchive(from: context)
        let missingCourseID = UUID()
        let invalidTask = BackupTask(
            id: UUID(),
            title: "无效任务",
            taskDescription: nil,
            createdAt: .now,
            updatedAt: .now,
            plannedDate: nil,
            startDate: nil,
            endDate: nil,
            deadline: nil,
            priorityRaw: TaskPriority.medium.rawValue,
            statusRaw: TaskStatus.active.rawValue,
            completedAt: nil,
            sortOrder: 0,
            courseID: missingCourseID,
            projectID: nil,
            assignmentID: nil,
            tagIDs: []
        )
        let invalidArchive = LifeOSBackupArchive(
            metadata: archive.metadata,
            preferences: archive.preferences,
            data: LifeOSBackupPayload(
                appConfigurations: [], habits: [], habitRecords: [], projects: [], tasks: [invalidTask], events: [], courses: [], sessions: [], assignments: [], exams: [], journalEntries: [], tags: []
            )
        )

        XCTAssertThrowsError(try LifeOSBackupService.validate(invalidArchive)) { error in
            XCTAssertEqual(error.localizedDescription, "备份校验未通过：备份中的关联数据不完整。")
        }
    }

    func testAutomaticBackupUpdatesDailySnapshotAndListsRecoveryPoints() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(Task(title: "需要保护的任务"))
        try context.save()

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LifeOSAutomaticBackups-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let snapshotDay = Date(timeIntervalSince1970: 1_800_000_000)
        let firstDailyURL = try LifeOSBackupService.createDailySnapshot(
            from: context,
            now: snapshotDay,
            automaticBackupDirectory: directory
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstDailyURL.path))

        context.insert(Event(title: "更新后的日程", startDate: snapshotDay))
        try context.save()
        let refreshedDailyURL = try LifeOSBackupService.createDailySnapshot(
            from: context,
            now: snapshotDay,
            automaticBackupDirectory: directory
        )
        XCTAssertEqual(firstDailyURL, refreshedDailyURL)
        XCTAssertEqual(try LifeOSBackupService.loadBackup(from: refreshedDailyURL).data.events.count, 1)

        let recoveryURL = try LifeOSBackupService.createRecoveryPoint(
            from: context,
            kind: .beforeTestDataImport,
            automaticBackupDirectory: directory
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryURL.path))

        let backups = LifeOSBackupService.automaticBackups(
            limit: 8,
            automaticBackupDirectory: directory
        )
        XCTAssertEqual(backups.count, 2)
        XCTAssertEqual(
            Set(backups.map { $0.kind.rawValue }),
            Set([LifeOSAutomaticBackupKind.daily.rawValue, LifeOSAutomaticBackupKind.beforeTestDataImport.rawValue])
        )
    }

    func testMonthCalendarLayoutBuildsAStableSixWeekGrid() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let august = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!
        let expectedFirstDay = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        let expectedLastDay = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6))!

        let days = MonthCalendarLayout.visibleDays(for: august, calendar: calendar)

        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.first, expectedFirstDay)
        XCTAssertEqual(days.last, expectedLastDay)
        XCTAssertEqual(MonthCalendarLayout.weekdaySymbols(calendar: calendar), ["一", "二", "三", "四", "五", "六", "日"])
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            AppConfiguration.self,
            Habit.self,
            HabitRecord.self,
            Project.self,
            Task.self,
            Event.self,
            Course.self,
            CourseSession.self,
            Assignment.self,
            Exam.self,
            JournalEntry.self,
            Tag.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
