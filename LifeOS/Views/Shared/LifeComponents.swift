import SwiftUI

/// A quiet paper-like surface used only where a distinct information group is useful.
struct LifeSurface<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(padding: CGFloat = AppSpacing.lg, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .stroke(AppColors.surfaceBorder, lineWidth: 1)
            }
    }
}

struct LifePageHeader: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            if let eyebrow {
                Text(eyebrow)
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.secondaryText)
            }
            Text(title)
                .font(AppTypography.pageTitle)
                .foregroundStyle(AppColors.primaryText)
            if let subtitle {
                Text(subtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
    }
}

struct LifeSectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.primaryText)
            if let subtitle {
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }
}

struct LifeMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Label(title, systemImage: symbol)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)
            Text(value)
                .font(AppTypography.metric)
                .foregroundStyle(AppColors.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(AppColors.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

struct LifeSidebarItem: View {
    let title: String
    let symbolName: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.sm)
                .background(background, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var background: Color {
        if isSelected { return AppColors.selectedSidebar }
        return isHovered ? AppColors.sidebarHover : .clear
    }
}

struct LifeSidebarTodayItem<MenuContent: View>: View {
    let symbolName: String
    let symbolColor: Color
    let isSelected: Bool
    let selectToday: () -> Void
    @ViewBuilder let menuContent: MenuContent
    @State private var isHovered = false

    init(
        symbolName: String,
        symbolColor: Color,
        isSelected: Bool,
        selectToday: @escaping () -> Void,
        @ViewBuilder menuContent: () -> MenuContent
    ) {
        self.symbolName = symbolName
        self.symbolColor = symbolColor
        self.isSelected = isSelected
        self.selectToday = selectToday
        self.menuContent = menuContent()
    }

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Button(action: selectToday) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: symbolName)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(symbolColor)
                        .frame(width: 18)
                    Text("今天")
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColors.primaryText)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("前往今天")

            Menu { menuContent } label: {
                Image(systemName: "chevron.down")
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(width: 18, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("设置今天天气")
            .accessibilityLabel("设置今天天气")
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.sm)
        .background(background, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .onHover { isHovered = $0 }
    }

    private var background: Color {
        if isSelected { return AppColors.selectedSidebar }
        return isHovered ? AppColors.sidebarHover : .clear
    }
}
