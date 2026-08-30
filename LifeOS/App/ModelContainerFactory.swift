import SwiftData

/// Creates the local SwiftData store used by the app.
enum ModelContainerFactory {
    static func make() -> ModelContainer {
        let schema = Schema([
            AppConfiguration.self,
            Habit.self, HabitRecord.self,
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
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法初始化本地数据存储：\(error.localizedDescription)")
        }
    }
}
