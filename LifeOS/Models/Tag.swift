import Foundation
import SwiftData

/// A reusable label shared by tasks and calendar events.
@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var name: String
    var colorHex: String
    var createdAt: Date

    @Relationship(inverse: \Task.tags) var tasks: [Task] = []
    @Relationship(inverse: \Event.tags) var events: [Event] = []

    init(name: String, colorHex: String = "#8E8E93") {
        id = UUID()
        self.name = name
        self.colorHex = colorHex
        createdAt = .now
    }
}
