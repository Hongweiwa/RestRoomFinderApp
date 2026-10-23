import SwiftUI

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var cornerRadius: CGFloat = AppTheme.Radius.control
    var iconAtEnd = false
    var isLoading = false
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.small) {
                if isLoading {
                    ProgressView().tint(AppTheme.background)
                        .accessibilityHidden(true)
                } else if let systemImage, !iconAtEnd {
                    Image(systemName: systemImage).accessibilityHidden(true)
                }
                Text(title).fixedSize(horizontal: false, vertical: true)
                if iconAtEnd, let systemImage {
                    Image(systemName: systemImage).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(AppButtonStyle(isPrimary: true, cornerRadius: cornerRadius, compact: compact))
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? "Loading" : "")
    }
}

/// Shared layout and interaction states for both button hierarchies.
struct AppButtonStyle: ButtonStyle {
    let isPrimary: Bool
    var cornerRadius: CGFloat = AppTheme.Radius.control
    var compact = false
    var horizontalPadding: CGFloat = AppTheme.Spacing.large
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? AppTheme.Typography.compactButton : AppTheme.Typography.button)
            .multilineTextAlignment(.center)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, AppTheme.Spacing.medium)
            .frame(maxWidth: .infinity, minHeight: AppTheme.Metrics.minimumTapTarget)
            .foregroundStyle(isPrimary ? AppTheme.background : AppTheme.foreground)
            .background(isPrimary ? AppTheme.foreground : AppTheme.background,
                        in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(AppTheme.foreground, lineWidth: AppTheme.Metrics.borderWidth)
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .opacity(!isEnabled ? AppTheme.Metrics.disabledOpacity :
                        (configuration.isPressed ? AppTheme.Metrics.pressedOpacity : 1))
    }
}
