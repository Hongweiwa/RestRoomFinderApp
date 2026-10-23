import SwiftUI

struct RestroomRow: View {
    let restroom: Restroom

    var body: some View {
        HStack(spacing: AppTheme.Spacing.large) {
            Image(systemName: restroom.imageName)
                .font(AppTheme.Typography.symbol)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(AppTheme.foreground)
                .frame(width: AppTheme.Metrics.symbolSize, height: AppTheme.Metrics.symbolSize)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text(restroom.name)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.foreground)
                Text(restroom.address)
                    .font(AppTheme.Typography.secondary)
                    .foregroundStyle(AppTheme.secondary)
            }
        }
    }
}
