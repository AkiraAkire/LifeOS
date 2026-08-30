import SwiftUI

/// Stage-0 placeholder that establishes Today as the default application surface.
struct TodayPlaceholderView: View {
    private let chineseLocale = Locale(identifier: "zh_CN")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting)
                        .font(.title2.weight(.semibold))

                    Text(todayText)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                ContentUnavailableView(
                    "今天还没有安排",
                    systemImage: "sun.max",
                    description: Text("点击右上角 ＋ 添加任务或日程。")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            }
            .padding(32)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11: "早上好"
        case 11..<14: "中午好"
        case 14..<18: "下午好"
        default: "晚上好"
        }
    }

    private var todayText: String {
        Date.now.formatted(
            .dateTime
                .locale(chineseLocale)
                .year()
                .month(.wide)
                .day()
                .weekday(.wide)
        )
    }
}

#Preview {
    TodayPlaceholderView()
}
