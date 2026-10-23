import SwiftUI

/// Shared auth gate and per-place action state. Cloud writes stay in FavoritesViewModel.
struct FavoriteButton: View {
    let restroom: Restroom
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var favorites: FavoritesViewModel
    @State private var showAuthentication = false
    @State private var error: String?
    @State private var checking = false
    private var saved: Bool {
        guard let id = auth.state.user?.id, favorites.userID == id else { return false }
        return favorites.isFavorite(restroom)
    }
    var body: some View {
        SecondaryButton(title: saved ? "SAVED" : "SAVE", systemImage: saved ? "heart.fill" : "heart",
                        cornerRadius: AppTheme.Radius.compact) {
            guard !checking else { return }
            checking = true
            Task {
                defer { checking = false }
                guard await auth.requireAuthentication(), let user = auth.state.user else {
                    showAuthentication = true; return
                }
                await favorites.load(user: user)
                error = await favorites.toggle(restroom, user: user)
            }
        }
        .disabled(checking || favorites.isPending(restroom) || (auth.state.user != nil && favorites.state == .loading))
        .accessibilityLabel(saved ? "Remove \(restroom.name) from saved restrooms" : "Save \(restroom.name)")
        .accessibilityValue(checking || favorites.isPending(restroom) ? "Updating" : saved ? "Saved" : "Not saved")
        .accessibilityIdentifier("favorite-toggle")
        .sheet(isPresented: $showAuthentication) { AuthenticationView(viewModel: auth) }
        .alert("Saved Restrooms", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
}
