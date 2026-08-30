import Foundation
import SwiftData

@Model
final class Habit {
    @Attribute(.unique) var id: UUID
    var name: String
    var symbolName: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \HabitRecord.habit) var records: [HabitRecord] = []
    init(name: String, symbolName: String = "checkmark.circle") { id = UUID(); self.name = name; self.symbolName = symbolName; createdAt = .now }
}

@Model
final class HabitRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var habit: Habit?
    init(date: Date = .now, habit: Habit? = nil) { id = UUID(); self.date = date; self.habit = habit }
}

enum HabitService {
    static func isCompleted(_ habit: Habit, on date: Date, calendar: Calendar = .current) -> Bool { habit.records.contains { calendar.isDate($0.date, inSameDayAs: date) } }
    static func toggle(_ habit: Habit, on date: Date, in context: ModelContext, calendar: Calendar = .current) {
        if let record = habit.records.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) { context.delete(record) }
        else { context.insert(HabitRecord(date: date, habit: habit)) }
        try? context.save()
    }
}
