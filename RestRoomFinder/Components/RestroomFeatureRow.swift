import SwiftUI

/// A nil attribute is unverified, distinct from a confirmed negative value.
struct RestroomFeatureRow: View {
    let title: String
    let systemImage: String
    let value: Bool?
    var availableText = "Available"
    var unavailableText = "Unavailable"

    private var status: String {
        switch value {
        case true: return availableText
        case false: return unavailableText
        default: return "Not yet verified"
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.Spacing.medium) {
                Label(title, systemImage: systemImage)
                Spacer(minLength: AppTheme.Spacing.medium)
                Text(status).foregroundStyle(AppTheme.secondary)
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Label(title, systemImage: systemImage)
                Text(status).foregroundStyle(AppTheme.secondary)
            }
        }
        .font(AppTheme.Typography.secondary)
        .padding(.vertical, AppTheme.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(status)")
    }
}
