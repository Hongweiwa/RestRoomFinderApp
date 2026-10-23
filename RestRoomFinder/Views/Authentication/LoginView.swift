import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: AuthViewModel
    let onCreateAccount: () -> Void
    let onContinueAsGuest: () -> Void
    @State private var email = ""
    @State private var password = ""
    @State private var showResetNotice = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.extraLarge) {
            Text("Welcome Back").font(AppTheme.Typography.title).accessibilityAddTraits(.isHeader)
            AuthTextField(title: "Email", text: $email, isEmail: true)
            AuthPasswordField(title: "Password", text: $password)
            if let message = viewModel.message { Text(message).font(AppTheme.Typography.caption).accessibilityIdentifier("auth-message") }
            PrimaryButton(title: "Log In", isLoading: viewModel.operation == .login) { submit() }
                .accessibilityIdentifier("auth-login-submit")
            Button("Forgot Password?") { showResetNotice = true }
                .frame(minHeight: AppTheme.Metrics.minimumTapTarget)
            SecondaryButton(title: "Create Account", action: onCreateAccount)
            Button("Continue as Guest", action: onContinueAsGuest)
                .frame(maxWidth: .infinity, minHeight: AppTheme.Metrics.minimumTapTarget)
        }
        .disabled(viewModel.isBusy)
        .onSubmit { submit() }
        .onDisappear { password = "" }
        .alert("Password reset", isPresented: $showResetNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Password reset is not available in the app yet. No reset email has been sent. You can continue using RestRoom Finder as a guest.")
        }
    }

    private func submit() {
        guard !viewModel.isBusy else { return }
        Task {
            await viewModel.login(email: email, password: password)
            password = ""
        }
    }
}
