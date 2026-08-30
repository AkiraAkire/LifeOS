import SwiftUI

/// Consistent temporary state for V1 modules that have not reached their implementation phase.
struct PlaceholderFeatureView: View {
    let destination: AppDestination

    var body: some View {
        ContentUnavailableView(
            "\(destination.title)正在准备中",
            systemImage: destination.symbolName,
            description: Text("该模块会按照 V1 开发计划逐步开放。")
        )
        .padding()
    }
}

#Preview {
    PlaceholderFeatureView(destination: .calendar)
}
