import SwiftUI

struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var cornerRadius: CGFloat = AppTheme.Radius.control
    var iconAtEnd = false
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.small) {
                if let systemImage, !iconAtEnd {
                    Image(systemName: systemImage).accessibilityHidden(true)
                }
                Text(title).fixedSize(horizontal: false, vertical: true)
                if iconAtEnd, let systemImage {
                    Image(systemName: systemImage).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(AppButtonStyle(isPrimary: false, cornerRadius: cornerRadius, compact: compact))
    }
}
