import SwiftUI

/// The same protected entry is used by Explore, Profile and My Submissions.
struct AddRestroomButton: View {
    var styled = true
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var submissions: MySubmissionsViewModel
    @State private var checking = false
    @State private var showPrompt = false
    @State private var authPage: AuthenticationView.Page?
    @State private var editor: Editor?
    private struct Editor: Identifiable { let id: UUID }
    var body: some View {
        Group {
            if styled { PrimaryButton(title: "Add a Restroom",systemImage: "plus",action: open) }
            else { Button(action: open) { Label("Add a Restroom",systemImage: "plus") } }
        }
        .disabled(checking || auth.state == .loading)
        .accessibilityIdentifier("add-restroom")
        .confirmationDialog("Sign in to submit a restroom.",isPresented: $showPrompt,titleVisibility: .visible) {
            Button("Create Account") { authPage = .signup }
            Button("Log In") { authPage = .login }
            Button("Cancel",role: .cancel) {}
        }
        .sheet(item: $authPage) { AuthenticationView(viewModel: auth,initialPage: $0) }
        .sheet(item: $editor) { context in
            AddRestroomView(service: submissions.service,userID: context.id,onSaved: submissions.didSave)
        }
        .onChange(of: auth.state.user?.id) { _, _ in editor = nil }
    }
    private func open() {
        guard !checking else { return }; checking = true
        Task {
            defer { checking = false }
            guard await auth.requireAuthentication(), let user = auth.state.user else { showPrompt = true; return }
            submissions.setUser(user)
            editor = Editor(id: user.id)
        }
    }
}
