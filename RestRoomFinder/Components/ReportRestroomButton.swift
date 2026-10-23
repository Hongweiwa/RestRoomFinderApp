import SwiftUI

/// Connects the existing Details action to the existing authentication flow.
struct ReportRestroomButton: View {
    let restroom: Restroom
    var placeAttributions: NSAttributedString? = nil
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var reports: MyReportsViewModel
    @State private var checking = false
    @State private var showPrompt = false
    @State private var authPage: AuthenticationView.Page?
    @State private var editor: Editor?
    private struct Editor: Identifiable { let id: UUID }
    var body: some View {
        SecondaryButton(title: "REPORT",systemImage: "exclamationmark.bubble.fill",cornerRadius: AppTheme.Radius.compact,action: open)
            .disabled(checking || auth.state == .loading)
            .accessibilityLabel("Report Incorrect Information")
            .accessibilityHint("Report a problem with this restroom's information")
            .accessibilityIdentifier("report-restroom")
            .confirmationDialog("Sign In Required",isPresented: $showPrompt,titleVisibility: .visible) {
                Button("Create Account") { authPage = .signup }
                Button("Log In") { authPage = .login }
                Button("Cancel",role: .cancel) {}
            } message: { Text("Create an account or log in to report incorrect restroom information.") }
            .sheet(item: $authPage) { AuthenticationView(viewModel: auth,initialPage: $0) }
            .sheet(item: $editor) { context in
                ReportView(service: reports.service,restroom: restroom,userID: context.id,placeAttributions: placeAttributions) {
                    reports.didSubmit($0,restroom: restroom)
                }
            }
            .onChange(of: auth.state.user?.id) { _, _ in editor = nil }
    }
    private func open() {
        guard !checking else { return }; checking = true
        Task {
            defer { checking = false }
            guard await auth.requireAuthentication(), let user = auth.state.user else { showPrompt = true; return }
            reports.setUser(user); editor = Editor(id: user.id)
        }
    }
}
