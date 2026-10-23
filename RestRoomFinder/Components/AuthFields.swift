import SwiftUI

struct AuthTextField: View {
    let title: String
    @Binding var text: String
    var isEmail = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text(title).font(AppTheme.Typography.headline)
            TextField(title, text: $text)
                .keyboardType(isEmail ? .emailAddress : .default)
                .textContentType(isEmail ? .username : .name)
                .textInputAutocapitalization(isEmail ? .never : .words)
                .autocorrectionDisabled()
                .authFieldSurface()
                .accessibilityIdentifier(isEmail ? "auth-email" : "auth-name")
        }
    }
}

struct AuthPasswordField: View {
    let title: String
    @Binding var text: String
    var isNewPassword = false
    var identifier = "auth-password"
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text(title).font(AppTheme.Typography.headline)
            HStack(spacing: AppTheme.Spacing.small) {
                Group {
                    if isVisible { TextField(title, text: $text) }
                    else { SecureField(title, text: $text) }
                }
                .textContentType(isNewPassword ? .newPassword : .password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier(identifier)
                Button { isVisible.toggle() } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .frame(minWidth: AppTheme.Metrics.minimumTapTarget, minHeight: AppTheme.Metrics.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isVisible ? "Hide" : "Show") \(title.lowercased())")
            }
            .authFieldSurface()
        }
    }
}

private extension View {
    func authFieldSurface() -> some View {
        self.padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)
            .frame(minHeight: AppTheme.Metrics.minimumTapTarget)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                    .strokeBorder(AppTheme.secondary.opacity(0.3), lineWidth: AppTheme.Metrics.borderWidth)
            }
    }
}
