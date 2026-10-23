import SwiftUI

/// Account entry and session controls only; the full Profile feature is deferred.
struct AuthenticationView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    enum Page: String, Identifiable {
        case welcome, login, signup
        var id: String { rawValue }
    }
    @State private var page: Page = .welcome

    init(viewModel: AuthViewModel, initialPage: Page = .welcome) {
        self.viewModel = viewModel
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch viewModel.state {
                    case .loading:
                        VStack(spacing: AppTheme.Spacing.large) {
                            ProgressView("Checking your session…")
                            Button("Continue browsing") { dismiss() }
                                .frame(minHeight: AppTheme.Metrics.minimumTapTarget)
                        }.frame(maxWidth: .infinity)
                    case .authenticated(let user): account(user)
                    case .guest:
                        if let email = viewModel.confirmationEmail { checkEmail(email) }
                        else {
                            switch page {
                            case .welcome: welcome
                            case .login: LoginView(viewModel: viewModel, onCreateAccount: { changePage(.signup) }, onContinueAsGuest: { dismiss() })
                            case .signup: CreateAccountView(viewModel: viewModel, onLogin: { changePage(.login) }, onContinueAsGuest: { dismiss() })
                            }
                        }
                    }
                }
                .padding(AppTheme.Spacing.extraLarge)
            }
            .scrollDismissesKeyboard(.interactively)
            .appScreenStyle()
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(viewModel.isBusy)
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isBusy)
        .onChange(of: viewModel.state.user?.id) { oldID, newID in
            if oldID == nil, newID != nil { dismiss() }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.extraLarge) {
            Text("RESTROOM FINDER").font(AppTheme.Typography.title).accessibilityAddTraits(.isHeader)
            Text("Find restrooms near you, save places across devices, and share restroom and cleanliness reviews.")
                .foregroundStyle(AppTheme.secondary)
            if let message = viewModel.message { Text(message).font(AppTheme.Typography.caption) }
            PrimaryButton(title: "Create Account") { changePage(.signup) }
            SecondaryButton(title: "Log In") { changePage(.login) }
            Button("Continue as Guest") { dismiss() }
                .frame(maxWidth: .infinity, minHeight: AppTheme.Metrics.minimumTapTarget)
        }
    }

    private func checkEmail(_ email: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.extraLarge) {
            Image(systemName: "envelope").font(AppTheme.Typography.title).accessibilityHidden(true)
            Text("Check your email").font(AppTheme.Typography.title).accessibilityAddTraits(.isHeader)
            Text("If signup was accepted, a confirmation link was sent to \(email). Verify your email before signing in.")
            Text("Open the link on this device to return to the app, or verify elsewhere and then log in here.")
                .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
            PrimaryButton(title: "Go to Log In") { changePage(.login) }
            SecondaryButton(title: "Continue as Guest") { dismiss() }
        }
    }

    private func account(_ user: AuthUser) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.extraLarge) {
            Text("Signed in").font(AppTheme.Typography.title).accessibilityAddTraits(.isHeader)
            if let name = viewModel.profile?.displayName, !name.isEmpty { Text(name).font(AppTheme.Typography.headline) }
            Text(user.email).textSelection(.enabled)
            if viewModel.profileState == .loading { ProgressView("Loading account…") }
            if viewModel.profileState == .unavailable {
                Text(AuthenticationFailure.profileUnavailable.localizedDescription).font(AppTheme.Typography.caption)
                SecondaryButton(title: "Retry Profile") { viewModel.retryProfile() }
            }
            if let message = viewModel.message { Text(message).font(AppTheme.Typography.caption) }
            PrimaryButton(title: "Continue Finding Restrooms") { dismiss() }
            SecondaryButton(title: viewModel.operation == .logout ? "Logging Out…" : "Log Out", systemImage: "rectangle.portrait.and.arrow.right") {
                Task { await viewModel.logout() }
            }
            .accessibilityIdentifier("auth-logout")
            Text("Logout signs out this device. It does not delete your account.")
                .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
        }
        .disabled(viewModel.isBusy)
    }

    private func changePage(_ page: Page) {
        viewModel.clearFormMessages()
        self.page = page
    }
}
