import SwiftUI

/// One Saved implementation, embedded in Profile navigation or presented from the existing Saved tab.
struct SavedRestroomsView: View {
    let onExplore: () -> Void
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var favorites: FavoritesViewModel
    @State private var authPage: AuthenticationView.Page?
    @State private var showProfile = false
    @State private var selectedAttributions: NSAttributedString?
    @State private var selectedRestroom: Restroom?
    @State private var directions: Restroom?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.large) {
                switch auth.state {
                case .loading: ProgressView("Checking your account…")
                case .guest:
                    ContentUnavailableView("Save your favorite places", systemImage: "heart", description:
                        Text("Create an account or log in to keep your saved restrooms across devices."))
                    PrimaryButton(title: "Create Account") { authPage = .signup }
                    SecondaryButton(title: "Log In") { authPage = .login }
                    Button("Explore Restrooms", action: onExplore).frame(minHeight: 44)
                case .authenticated(let user):
                    if favorites.userID != user.id { ProgressView("Loading saved restrooms…") }
                    else { content(user: user) }
                }
            }.padding(AppTheme.Spacing.extraLarge)
        }
        .appScreenStyle()
        .navigationTitle("Saved Restrooms").navigationBarTitleDisplayMode(.inline)
        .refreshable {
            guard !favorites.hydrating else { return }
            await favorites.load(user: auth.state.user, force: true)
            await favorites.hydrate(force: true)
        }
        .task(id: auth.state) { await favorites.load(user: auth.state.user) }
        .onChange(of: favorites.state, initial: true) { _, state in
            if state == .loaded { Task { await favorites.hydrate() } }
        }
        .navigationDestination(isPresented: Binding(get: { selectedRestroom != nil }, set: { if !$0 { selectedRestroom = nil } })) {
            if let restroom = selectedRestroom { RestroomDetailView(restroom: restroom, placeAttributions: selectedAttributions) }
        }
        .onChange(of: auth.state.user?.id) { _, _ in selectedRestroom = nil; selectedAttributions = nil; directions = nil }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppBottomBar(selectedTab: .saved, onFind: onExplore, onSaved: {}, onProfile: { showProfile = true })
        }
        .sheet(item: $authPage) { AuthenticationView(viewModel: auth, initialPage: $0) }
        .sheet(item: $directions) { DirectionsView(restroom: $0) }
        .fullScreenCover(isPresented: $showProfile) { ProfileView() }
        .alert("Saved Restrooms", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
    @ViewBuilder private func content(user: AuthUser) -> some View {
        switch favorites.state {
        case .idle, .loading: ProgressView("Loading saved restrooms…")
        case .error(let message):
            ContentUnavailableView("Unable to load saved restrooms", systemImage: "wifi.exclamationmark", description: Text(message))
            SecondaryButton(title: "Retry") { Task { await favorites.load(user: user, force: true) } }
        case .loaded:
            if favorites.records.isEmpty {
                ContentUnavailableView("No Saved Restrooms Yet", systemImage: "heart", description:
                    Text("Tap the heart on a restroom to save it for quick access later."))
                PrimaryButton(title: "Explore Restrooms", action: onExplore)
            } else {
                if favorites.hydrating { ProgressView("Refreshing place information…").font(AppTheme.Typography.caption) }
                ForEach(favorites.records) { record in
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        if let restroom = favorites.restroom(for: record) {
                            RestroomCard(restroom: restroom, onDirections: { directions = restroom }, onOpenDetails: { selectedAttributions = favorites.details[record.id]?.attributions; selectedRestroom = restroom })
                            if restroom.googlePlaceID != nil {
                                Text("Google Maps").font(.footnote).foregroundStyle(AppTheme.secondary)
                                if let attribution = favorites.details[record.id]?.attributions {
                                    Text(AttributedString(attribution)).font(AppTheme.Typography.caption)
                                }
                            }
                            if favorites.detailFailures.contains(record.id) {
                                Text("Couldn't refresh this place. Showing information from this session.").font(AppTheme.Typography.caption)
                            }
                        } else {
                            Label(record.restroom == nil ? "Saved restroom unavailable" : "Place information unavailable", systemImage: "mappin.slash")
                                .font(AppTheme.Typography.headline)
                            Text("Your saved relationship is still here. Pull to refresh place information or remove it below.")
                                .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                        }
                        Button {
                            Task { error = await favorites.remove(record, user: user) }
                        } label: {
                            Label("Remove from Saved", systemImage: "heart.fill")
                                .frame(minHeight: AppTheme.Metrics.minimumTapTarget)
                        }
                        .disabled(!favorites.pending.isEmpty && favorites.pending.contains(record.restroom?.googlePlaceID.map { "google:\($0)" } ?? record.id.uuidString))
                        .accessibilityLabel("Remove \(favorites.restroom(for: record)?.name ?? "this restroom") from saved restrooms")
                    }
                    .padding(.bottom, AppTheme.Spacing.large)
                }
            }
        }
    }
}

struct SavedRestroomsScreen: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { SavedRestroomsView(onExplore: { dismiss() })
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.tint(AppTheme.foreground)
    }
}
