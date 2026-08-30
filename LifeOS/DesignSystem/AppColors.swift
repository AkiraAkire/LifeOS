import SwiftUI

/// Semantic color tokens for LifeOS. Values live in the asset catalog so light
/// and dark appearances remain coordinated without hard-coded view colors.
enum AppColors {
    static let canvas = Color("LifeCanvas")
    static let sidebar = Color("LifeSidebar")
    static let surface = Color("LifeSurface")
    static let primaryText = Color("LifePrimaryText")
    static let secondaryText = Color("LifeSecondaryText")
    static let divider = Color("LifeDivider")

    static let accent = Color("LifeAccent")
    static let course = Color("LifeCourse")
    static let task = Color("LifeTask")
    static let journal = Color("LifeJournal")
    static let calendar = Color("LifeCalendar")
    static let deadline = Color("LifeDeadline")

    static let selectedSidebar = accent.opacity(0.16)
    static let sidebarHover = primaryText.opacity(0.055)
    static let surfaceBorder = divider.opacity(0.72)
}
