import SwiftData
import SwiftUI

/// Owns the top-level macOS split-view navigation for the application.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("launchDestination") private var launchDestinationRaw = AppDestination.today.rawValue
    @AppStorage("appearance") private var appearance = "system"
    @StateObject private var navigation = AppNavigationCoordinator()
    @State private var hasStartedAutomaticProtection = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: destinationBinding)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            destinationView
                .navigationTitle(navigation.destination.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.canvas)
        }
        .tint(AppColors.accent)
        .preferredColorScheme(preferredColorScheme)
        .environmentObject(navigation)
        .onAppear {
            navigation.destination = AppDestination(rawValue: launchDestinationRaw) ?? .today
            guard !hasStartedAutomaticProtection else { return }
            hasStartedAutomaticProtection = true
            updateDailyProtection()
        }
        .onChange(of: scenePhase) { _, phase in
            // On macOS this runs when the app is no longer active as well as
            // when it backgrounds. The daily archive is overwritten in place,
            // so repeated transitions do not create backup clutter.
            guard hasStartedAutomaticProtection, (phase == .inactive || phase == .background) else { return }
            updateDailyProtection()
        }
    }

    private var destinationBinding: Binding<AppDestination?> {
        Binding(
            get: { navigation.destination },
            set: { navigation.destination = $0 ?? .today }
        )
    }

    @ViewBuilder
    private var destinationView: some View {
        switch navigation.destination {
        case .today:
            TodayView()
        case .calendar:
            CalendarView()
        case .tasks:
            TasksView()
        case .timetable:
            TimetableView()
        case .courses:
            CoursesView()
        case .journal:
            JournalView()
        case .settings:
            SettingsView()
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private func updateDailyProtection() {
        do {
            try LifeOSBackupService.createDailySnapshot(from: modelContext)
        } catch {
            // Data editing remains available if the private backup directory is
            // temporarily unavailable; the Settings page still exposes a clear
            // error when the user explicitly creates a snapshot.
            NSLog("LifeOS automatic backup failed: %@", error.localizedDescription)
        }
    }
}

#Preview {
    RootView()
}
