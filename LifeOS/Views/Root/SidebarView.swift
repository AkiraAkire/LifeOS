import SwiftData
import SwiftUI

/// Native-style sidebar containing the V1 navigation destinations.
struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalEntry.date, order: .reverse) private var journalEntries: [JournalEntry]
    @Binding var selection: AppDestination?

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    todayNavigationRow
                        .sidebarListRow()
                }

                Section("生活") {
                    navigationRow(for: .calendar)
                    navigationRow(for: .tasks)
                    navigationRow(for: .timetable)
                    navigationRow(for: .courses)
                    navigationRow(for: .journal)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(AppColors.sidebar)

            Rectangle()
                .fill(AppColors.divider.opacity(0.7))
                .frame(height: 1)

            LifeSidebarItem(
                title: AppDestination.settings.title,
                symbolName: AppDestination.settings.symbolName,
                isSelected: selection == .settings,
                action: { select(.settings) }
            )
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, AppSpacing.xs)
        }
        .background(AppColors.sidebar)
    }

    @ViewBuilder
    private func navigationRow(for destination: AppDestination) -> some View {
        LifeSidebarItem(
            title: destination.title,
            symbolName: destination.symbolName,
            isSelected: selection == destination,
            action: { select(destination) }
        )
        .sidebarListRow()
    }

    private var todayNavigationRow: some View {
        LifeSidebarTodayItem(
            symbolName: todayWeather?.symbolName ?? AppDestination.today.symbolName,
            symbolColor: todayWeather?.tintColor ?? AppColors.journal,
            isSelected: selection == .today,
            selectToday: { select(.today) }
        ) {
                ForEach(WeatherCondition.allCases, id: \.self) { weather in
                    Button {
                        setTodayWeather(weather)
                    } label: {
                        Label(weather.displayName, systemImage: weather.symbolName)
                    }
                }
        }
    }

    private var todayWeather: WeatherCondition? {
        JournalEntryService.entry(on: .now, in: journalEntries)?.weather
    }

    private func setTodayWeather(_ weather: WeatherCondition) {
        _ = JournalEntryService.setWeather(
            weather,
            for: .now,
            in: journalEntries,
            modelContext: modelContext
        )
    }

    private func select(_ destination: AppDestination) {
        withAnimation(.easeInOut(duration: 0.18)) {
            selection = destination
        }
    }
}

private extension View {
    func sidebarListRow() -> some View {
        listRowInsets(EdgeInsets(top: 2, leading: AppSpacing.xs, bottom: 2, trailing: AppSpacing.xs))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

#Preview {
    SidebarView(selection: .constant(.today))
        .frame(width: 220, height: 500)
}
