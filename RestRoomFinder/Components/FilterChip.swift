import SwiftUI

/// Selection is owned by the caller; this component performs no filtering.
struct FilterChip: View {
    let title: String
    var showsCheckmark = true
    var compact = false
    @Binding var isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { isSelected.toggle() } label: {
            HStack(spacing: AppTheme.Spacing.small) {
                if isSelected && showsCheckmark {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                }
                Text(title).fixedSize(horizontal: false, vertical: true)
            }
            .font(compact ? AppTheme.Typography.badge : AppTheme.Typography.caption.weight(.semibold))
            .padding(.horizontal, compact ? AppTheme.Spacing.medium : AppTheme.Spacing.large)
            .padding(.vertical, AppTheme.Spacing.small)
            .foregroundStyle(isSelected ? AppTheme.background : AppTheme.foreground)
            .background(isSelected ? AppTheme.foreground : AppTheme.surface, in: Capsule())
            .frame(minWidth: AppTheme.Metrics.minimumTapTarget,
                   minHeight: AppTheme.Metrics.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : AppTheme.Metrics.disabledOpacity)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
