import SwiftUI

/// Shared monochrome navigation strip used by Home and Restroom Details.
struct AppBottomBar: View {
    enum Tab { case find, saved, profile }
    var selectedTab: Tab = .find
    let onFind: () -> Void
    let onSaved: () -> Void
    let onProfile: () -> Void

    var body: some View {
        HStack {
            tab("FIND", symbol: "mappin.circle.fill", selected: selectedTab == .find, action: onFind)
            tab("SAVED", symbol: "bookmark.fill", selected: selectedTab == .saved, action: onSaved)
            tab("PROFILE", symbol: "person.fill", selected: selectedTab == .profile, action: onProfile)
        }
        .padding(.vertical, AppTheme.Spacing.small)
        .background(AppTheme.background)
        .overlay(alignment: .top) { Divider() }
    }

    private func tab(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: symbol).font(AppTheme.Typography.symbol)
                Text(title).font(AppTheme.Typography.badge).lineLimit(1).minimumScaleFactor(0.75)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.vertical, AppTheme.Spacing.small)
            .foregroundStyle(selected ? AppTheme.background : AppTheme.secondary)
            .background(selected ? AppTheme.foreground : .clear, in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact))
            .frame(maxWidth: .infinity, minHeight: AppTheme.Metrics.minimumTapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
