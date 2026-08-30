import SwiftUI

/// Typography hierarchy based entirely on the system San Francisco family.
enum AppTypography {
    static let pageTitle = Font.system(size: 28, weight: .semibold)
    static let editorialDate = Font.system(size: 24, weight: .semibold)
    static let sectionTitle = Font.system(size: 16, weight: .semibold)
    static let metric = Font.system(size: 26, weight: .medium, design: .rounded)
    static let body = Font.system(size: 15)
    static let bodyEmphasis = Font.system(size: 15, weight: .medium)
    static let metadata = Font.system(size: 13)
    static let caption = Font.system(size: 12)
    static let timelineTime = Font.system(size: 13, weight: .medium, design: .monospaced)
}
