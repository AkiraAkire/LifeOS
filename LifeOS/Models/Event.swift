import Foundation
import SwiftData

/// A user-created calendar event such as an appointment, meeting, or personal plan.
@Model
final class Event {
    @Attribute(.unique) var id: UUID
    var title: String
    var eventDescription: String?
    var startDate: Date
    var endDate: Date?
    var isAllDay: Bool
    var eventTypeRaw: String
    var location: String?
    var createdAt: Date
    var updatedAt: Date

    var course: Course?
    var tags: [Tag] = []

    var eventType: EventType {
        get { EventType(rawValue: eventTypeRaw) ?? .personal }
        set { eventTypeRaw = newValue.rawValue }
    }

    init(
        title: String,
        startDate: Date,
        endDate: Date? = nil,
        isAllDay: Bool = false,
        eventType: EventType = .personal,
        eventDescription: String? = nil,
        location: String? = nil
    ) {
        id = UUID()
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        eventTypeRaw = eventType.rawValue
        self.eventDescription = eventDescription
        self.location = location
        createdAt = .now
        updatedAt = .now
    }
}
