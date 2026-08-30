import Foundation
import SwiftUI

enum TaskPriority: String, Codable, CaseIterable {
    case high
    case medium
    case low

    var displayName: String {
        switch self {
        case .high: "高"
        case .medium: "中"
        case .low: "低"
        }
    }
}

enum TaskStatus: String, Codable, CaseIterable {
    case inbox
    case active
    case completed
    case archived
}

enum EventType: String, Codable, CaseIterable {
    case personal
    case course
    case exam
    case deadline
}

enum Mood: String, Codable, CaseIterable {
    case excellent
    case good
    case neutral
    case low
    case bad

    var displayName: String {
        switch self {
        case .excellent: "非常好"
        case .good: "不错"
        case .neutral: "一般"
        case .low: "不太好"
        case .bad: "很差"
        }
    }

    var symbol: String {
        switch self {
        case .excellent: "😄"
        case .good: "🙂"
        case .neutral: "😐"
        case .low: "😔"
        case .bad: "😫"
        }
    }
}

enum WeatherCondition: String, Codable, CaseIterable {
    case sunny
    case cloudy
    case rainy

    var displayName: String {
        switch self {
        case .sunny: "晴天"
        case .cloudy: "阴天"
        case .rainy: "雨天"
        }
    }

    var symbolName: String {
        switch self {
        case .sunny: "sun.max.fill"
        case .cloudy: "cloud.fill"
        case .rainy: "cloud.rain.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .sunny: .orange
        case .cloudy: .gray
        case .rainy: .blue
        }
    }
}

enum Weekday: Int, Codable, CaseIterable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
}

/// Defines which teaching weeks a recurring course session occurs in.
enum WeekPattern: String, Codable, CaseIterable {
    case all
    case odd
    case even

    var displayName: String {
        switch self {
        case .all: "每周"
        case .odd: "单周"
        case .even: "双周"
        }
    }
}
