import SwiftUI

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var isEyebrow = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(title)
                .font(isEyebrow ? AppTheme.Typography.eyebrow : AppTheme.Typography.headline)
                .tracking(isEyebrow ? 1.5 : 0)
                .foregroundStyle(AppTheme.foreground)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(AppTheme.Typography.secondary)
                    .foregroundStyle(AppTheme.secondary)
            }
        }
        .textCase(nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.medium)
    }
}
