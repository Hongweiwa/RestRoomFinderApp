import SwiftUI

struct CreateAccountView: View {
    @ObservedObject var viewModel: AuthViewModel
    let onLogin: () -> Void
    let onContinueAsGuest: () -> Void
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.extraLarge) {
            Text("Create Account").font(AppTheme.Typography.title).accessibilityAddTraits(.isHeader)
            AuthTextField(title: "Name", text: $name)
            AuthTextField(title: "Email", text: $email, isEmail: true)
            AuthPasswordField(title: "Password", text: $password, isNewPassword: true)
            Text("At least 8 characters. Additional requirements from your account service may apply.")
                .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
            AuthPasswordField(title: "Confirm Password", text: $confirmation, isNewPassword: true, identifier: "auth-confirm-password")
            if let message = viewModel.message { Text(message).font(AppTheme.Typography.caption).accessibilityIdentifier("auth-message") }
            PrimaryButton(title: "Create Account", isLoading: viewModel.operation == .signup) { submit() }
                .accessibilityIdentifier("auth-signup-submit")
            SecondaryButton(title: "Already have an account? Log In", action: onLogin)
            Button("Continue as Guest", action: onContinueAsGuest)
                .frame(maxWidth: .infinity, minHeight: AppTheme.Metrics.minimumTapTarget)
        }
        .disabled(viewModel.isBusy)
        .onSubmit { submit() }
        .onDisappear { password = ""; confirmation = "" }
    }

    private func submit() {
        guard !viewModel.isBusy else { return }
        Task {
            await viewModel.signup(name: name, email: email, password: password, confirmation: confirmation)
            password = ""
            confirmation = ""
        }
    }
}
