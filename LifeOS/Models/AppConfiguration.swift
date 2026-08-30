import Foundation
import SwiftData

/// Persistent application-level configuration placeholder for the V1 settings phase.
@Model
final class AppConfiguration {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    init(id: UUID = UUID(), createdAt: Date = .now) {
        self.id = id
        self.createdAt = createdAt
    }
}

/// A user-configurable row in the weekly timetable. It is a display preference,
/// while CourseSession remains the durable source of truth for class times.
struct TimetablePeriod: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var startTimeMinutes: Int
    var endTimeMinutes: Int

    init(
        id: UUID = UUID(),
        name: String,
        startTimeMinutes: Int,
        endTimeMinutes: Int
    ) {
        self.id = id
        self.name = name
        self.startTimeMinutes = startTimeMinutes
        self.endTimeMinutes = endTimeMinutes
    }

    var durationMinutes: Int { endTimeMinutes - startTimeMinutes }

    static let defaultPeriods: [TimetablePeriod] = [
        TimetablePeriod(name: "第 1 节", startTimeMinutes: 8 * 60, endTimeMinutes: 8 * 60 + 45),
        TimetablePeriod(name: "第 2 节", startTimeMinutes: 8 * 60 + 55, endTimeMinutes: 9 * 60 + 40),
        TimetablePeriod(name: "第 3 节", startTimeMinutes: 10 * 60 + 10, endTimeMinutes: 10 * 60 + 55),
        TimetablePeriod(name: "第 4 节", startTimeMinutes: 11 * 60 + 5, endTimeMinutes: 11 * 60 + 50),
        TimetablePeriod(name: "第 5 节", startTimeMinutes: 14 * 60, endTimeMinutes: 14 * 60 + 45),
        TimetablePeriod(name: "第 6 节", startTimeMinutes: 14 * 60 + 55, endTimeMinutes: 15 * 60 + 40),
        TimetablePeriod(name: "第 7 节", startTimeMinutes: 16 * 60 + 10, endTimeMinutes: 16 * 60 + 55),
        TimetablePeriod(name: "第 8 节", startTimeMinutes: 17 * 60 + 5, endTimeMinutes: 17 * 60 + 50),
        TimetablePeriod(name: "第 9 节", startTimeMinutes: 19 * 60, endTimeMinutes: 19 * 60 + 45),
        TimetablePeriod(name: "第 10 节", startTimeMinutes: 19 * 60 + 55, endTimeMinutes: 20 * 60 + 40)
    ]

    static func validationMessage(for periods: [TimetablePeriod]) -> String? {
        guard !periods.isEmpty else { return "请至少保留一个课表节次。" }

        let sorted = periods.sorted { $0.startTimeMinutes < $1.startTimeMinutes }
        for period in sorted {
            guard !period.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "每个节次都需要名称。"
            }
            guard period.startTimeMinutes < period.endTimeMinutes else {
                return "结束时间需要晚于开始时间。"
            }
        }

        for (previous, next) in zip(sorted, sorted.dropFirst()) where previous.endTimeMinutes > next.startTimeMinutes {
            return "节次时间不能重叠。"
        }
        return nil
    }
}

/// Keeps timetable display preferences local without coupling them to course data.
enum TimetablePeriodStore {
    private static let storageKey = "timetablePeriods"

    static func load() -> [TimetablePeriod] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let periods = try? JSONDecoder().decode([TimetablePeriod].self, from: data),
              TimetablePeriod.validationMessage(for: periods) == nil
        else {
            return TimetablePeriod.defaultPeriods
        }
        return periods.sorted { $0.startTimeMinutes < $1.startTimeMinutes }
    }

    static func save(_ periods: [TimetablePeriod]) {
        let sorted = periods.sorted { $0.startTimeMinutes < $1.startTimeMinutes }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

/// The academic date range used to calculate semester week numbers.
struct SemesterDateRange: Codable, Equatable {
    var startDate: Date
    var endDate: Date

    init(startDate: Date, endDate: Date, calendar: Calendar = .current) {
        self.startDate = calendar.startOfDay(for: startDate)
        self.endDate = calendar.startOfDay(for: endDate)
    }

    func weekNumber(containing date: Date, calendar: Calendar = .current) -> Int? {
        let day = calendar.startOfDay(for: date)
        let firstWeekStart = Self.monday(containing: startDate, calendar: calendar)
        guard day >= firstWeekStart, day <= endDate else { return nil }
        let days = calendar.dateComponents([.day], from: firstWeekStart, to: day).day ?? 0
        return days / 7 + 1
    }

    func weekCount(calendar: Calendar = .current) -> Int {
        weekNumber(containing: endDate, calendar: calendar) ?? 1
    }

    static func endDate(
        forWeekCount weekCount: Int,
        startDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        let firstWeekStart = monday(containing: startDate, calendar: calendar)
        return calendar.date(byAdding: .day, value: max(1, weekCount) * 7 - 1, to: firstWeekStart)
            ?? calendar.startOfDay(for: startDate)
    }

    static func monday(containing date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }

    var isValid: Bool { endDate >= startDate }

    static func defaultRange(now: Date = .now, calendar: Calendar = .current) -> SemesterDateRange {
        let today = calendar.startOfDay(for: now)
        let monday = monday(containing: today, calendar: calendar)
        let end = endDate(forWeekCount: 18, startDate: monday, calendar: calendar)
        return SemesterDateRange(startDate: monday, endDate: end, calendar: calendar)
    }
}

/// Stores the current semester locally without coupling a display preference to SwiftData.
enum SemesterDateRangeStore {
    private static let storageKey = "semesterDateRange"

    static func load(defaultNow: Date = .now, calendar: Calendar = .current) -> SemesterDateRange {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let range = try? JSONDecoder().decode(SemesterDateRange.self, from: data),
              range.isValid
        else {
            return .defaultRange(now: defaultNow, calendar: calendar)
        }
        return range
    }

    static func save(_ range: SemesterDateRange) {
        guard range.isValid, let data = try? JSONEncoder().encode(range) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

enum SemesterDateRangeCoordinator {
    static func applyGlobalRange(_ range: SemesterDateRange, to courses: [Course]) {
        for course in courses where course.usesSemesterDateRange {
            course.updateSessionDates(to: range)
        }
    }
}
