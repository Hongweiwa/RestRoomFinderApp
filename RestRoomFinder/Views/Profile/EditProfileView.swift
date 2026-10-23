import SwiftUI

struct EditProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    let user: AuthUser
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var discardChanges = false
    @FocusState private var nameFocused: Bool
    private var hasChanges: Bool { name != (viewModel.profile?.displayName ?? "") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.extraLarge) {
                ProfileAvatar(name: viewModel.profile?.displayName).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Text("Display Name").font(AppTheme.Typography.headline)
                    TextField("Your display name", text: $name)
                        .textContentType(.name).textInputAutocapitalization(.words).autocorrectionDisabled()
                        .submitLabel(.done).focused($nameFocused)
                        .padding(AppTheme.Spacing.large)
                        .frame(minHeight: AppTheme.Metrics.minimumTapTarget)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
                        .accessibilityLabel("Display name").accessibilityIdentifier("profile-edit-name")
                    Text("Use 1–50 characters. Your name appears with your future contributions.")
                        .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Text("Email").font(AppTheme.Typography.headline)
                    Text(user.email).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Text("Email is managed by your account and cannot be changed here.")
                        .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(AppTheme.Spacing.large)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
                if case .error(let message) = viewModel.saveState {
                    Label(message, systemImage: "exclamationmark.circle").font(AppTheme.Typography.caption)
                        .accessibilityIdentifier("profile-save-error")
                }
                PrimaryButton(title: "Save Changes", isLoading: viewModel.isSaving, action: save)
                    .disabled(!hasChanges).accessibilityIdentifier("profile-save")
            }
            .padding(AppTheme.Spacing.extraLarge).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively).appScreenStyle()
        .navigationTitle("Edit Profile").navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if hasChanges { discardChanges = true } else { dismiss() } }.disabled(viewModel.isSaving)
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { nameFocused = false } }
        }
        .disabled(viewModel.isSaving)
        .confirmationDialog("Discard changes?", isPresented: $discardChanges, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .onAppear { name = viewModel.profile?.displayName ?? ""; viewModel.clearSaveError() }
        .onChange(of: auth.state.user?.id) { _, id in if id != user.id { dismiss() } }
    }
    private func save() {
        guard !viewModel.isSaving else { return }
        nameFocused = false
        Task { if await viewModel.save(name: name) { auth.retryProfile(); dismiss() } }
    }
}
