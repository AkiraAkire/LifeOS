import Foundation
import SwiftData

/// A low-friction daily reflection. The journal service will enforce one entry per calendar day.
@Model
final class JournalEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var moodRaw: String?
    /// Optional for a lightweight SwiftData migration from journals without weather.
    var weatherRaw: String?
    var quote: String?
    var content: String?
    var importantEvents: String?
    var createdAt: Date
    var updatedAt: Date

    var mood: Mood? {
        get { moodRaw.flatMap(Mood.init(rawValue:)) }
        set { moodRaw = newValue?.rawValue }
    }

    var weather: WeatherCondition? {
        get { weatherRaw.flatMap(WeatherCondition.init(rawValue:)) }
        set { weatherRaw = newValue?.rawValue }
    }

    init(
        date: Date,
        mood: Mood? = nil,
        weather: WeatherCondition? = nil,
        quote: String? = nil,
        content: String? = nil,
        importantEvents: String? = nil
    ) {
        id = UUID()
        self.date = date
        moodRaw = mood?.rawValue
        weatherRaw = weather?.rawValue
        self.quote = quote
        self.content = content
        self.importantEvents = importantEvents
        createdAt = .now
        updatedAt = .now
    }
}

/// Keeps one durable journal entry for each selected natural day.
enum JournalEntryService {
    static func entry(on date: Date, in entries: [JournalEntry], calendar: Calendar = .current) -> JournalEntry? {
        entries.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Creates an empty entry only when Calendar explicitly asks to start a
    /// reflection for the selected day. Reuses the same natural-day entry so
    /// opening Journal from Calendar can never create duplicates.
    @discardableResult
    static func ensureEntry(
        for date: Date,
        in entries: [JournalEntry],
        modelContext: ModelContext,
        calendar: Calendar = .current
    ) -> JournalEntry {
        if let existing = entry(on: date, in: entries, calendar: calendar) {
            return existing
        }

        let newEntry = JournalEntry(date: calendar.startOfDay(for: date))
        modelContext.insert(newEntry)
        try? modelContext.save()
        return newEntry
    }

    /// Updates only the weather field so quick controls never overwrite journal text or mood.
    @discardableResult
    static func setWeather(
        _ weather: WeatherCondition,
        for date: Date,
        in entries: [JournalEntry],
        modelContext: ModelContext,
        calendar: Calendar = .current
    ) -> JournalEntry {
        if let entry = entry(on: date, in: entries, calendar: calendar) {
            entry.weather = weather
            entry.updatedAt = .now
            try? modelContext.save()
            return entry
        }

        let newEntry = JournalEntry(date: date, weather: weather)
        modelContext.insert(newEntry)
        try? modelContext.save()
        return newEntry
    }

    @discardableResult
    static func save(
        entry: JournalEntry?,
        date: Date,
        mood: Mood?,
        weather: WeatherCondition? = nil,
        quote: String?,
        content: String?,
        importantEvents: String?,
        in modelContext: ModelContext
    ) -> JournalEntry {
        if let entry {
            entry.mood = mood
            entry.weather = weather
            entry.quote = quote
            entry.content = content
            entry.importantEvents = importantEvents
            entry.updatedAt = .now
            try? modelContext.save()
            return entry
        }

        let newEntry = JournalEntry(
            date: date,
            mood: mood,
            weather: weather,
            quote: quote,
            content: content,
            importantEvents: importantEvents
        )
        modelContext.insert(newEntry)
        try? modelContext.save()
        return newEntry
    }

    /// Deletes only the supplied daily entry. Callers decide which day is selected.
    static func delete(_ entry: JournalEntry, in modelContext: ModelContext) throws {
        modelContext.delete(entry)
        try modelContext.save()
    }
}
