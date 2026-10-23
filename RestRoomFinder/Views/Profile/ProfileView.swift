import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ProfileViewModel(service: ProfileService())
    @State private var authPage: AuthenticationView.Page?
    @State private var confirmLogout = false
    @State private var showSaved = false
    @State private var path: [Destination] = []

    private enum Destination: String, Hashable {
        case edit, saved = "Saved Restrooms", reviews = "My Reviews", submissions = "My Submissions"
        case reports = "My Reports", account = "Account Settings", privacy = "Privacy", help = "Help & Support"
        var symbol: String {
            switch self {
            case .edit: return "pencil"
            case .saved: return "bookmark"
            case .reviews: return "star"
            case .submissions: return "mappin.and.ellipse"
            case .reports: return "exclamationmark.bubble"
            case .account: return "gearshape"
            case .privacy: return "lock.shield"
            case .help: return "questionmark.circle"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.extraLarge) {
                    switch auth.state {
                    case .loading: loading("Checking your account…")
                    case .guest: guest
                    case .authenticated(let user): authenticated(user)
                    }
                }
                .padding(AppTheme.Spacing.extraLarge)
                .frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .refreshable { await viewModel.load(user: auth.state.user) }
            .navigationTitle("Profile").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "arrow.left") }
                        .accessibilityLabel("Back to restrooms").disabled(auth.isBusy)
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                if destination == .edit {
                    if let user = auth.state.user, viewModel.profile?.id == user.id {
                        EditProfileView(viewModel: viewModel, user: user)
                    }
                } else if destination == .saved {
                    SavedRestroomsView(onExplore: { dismiss() })
                } else if destination == .reviews {
                    MyReviewsView(onExplore: { dismiss() })
                } else if destination == .submissions {
                    MySubmissionsView()
                } else if destination == .reports {
                    MyReportsView()
                } else {
                    ContentUnavailableView {
                        Label(destination.rawValue, systemImage: destination.symbol)
                    } description: {
                        Text("This feature is coming in a future update.")
                    }
                    .navigationTitle(destination.rawValue).appScreenStyle()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AppBottomBar(selectedTab: .profile, onFind: { dismiss() },
                    onSaved: { showSaved = true }, onProfile: {})
                    .disabled(auth.isBusy)
            }
            .appScreenStyle()
        }
        .tint(AppTheme.foreground)
        .sheet(item: $authPage) { AuthenticationView(viewModel: auth, initialPage: $0) }
        .confirmationDialog("Log Out?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) { Task { await auth.logout() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You can continue using RestRoom Finder as a guest.") }
        .fullScreenCover(isPresented: $showSaved) { SavedRestroomsScreen() }
        .onChange(of: auth.state) { _, state in
            if viewModel.user?.id != state.user?.id { path.removeAll(); confirmLogout = false }
            viewModel.setUser(state.user)
        }
        .task(id: auth.state) { await viewModel.load(user: auth.state.user) }
    }

    private var guest: some View {
        VStack(spacing: AppTheme.Spacing.extraLarge) {
            ProfileAvatar(isGuest: true)
            VStack(spacing: AppTheme.Spacing.small) {
                Text("Browsing as Guest").font(AppTheme.Typography.title).accessibilityAddTraits(.isHeader)
                Text("Create an account to save restrooms across devices and share restroom reviews.")
                    .foregroundStyle(AppTheme.secondary)
                Text("Finding a restroom is always open to guests.")
                    .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
            }.multilineTextAlignment(.center)
            VStack(spacing: AppTheme.Spacing.medium) {
                PrimaryButton(title: "Create Account") { authPage = .signup }
                    .accessibilityIdentifier("profile-create-account")
                SecondaryButton(title: "Log In") { authPage = .login }
                    .accessibilityIdentifier("profile-login")
                AddRestroomButton(styled: false)
            }
            if let message = auth.message { Text(message).font(AppTheme.Typography.caption) }
        }.padding(.vertical, AppTheme.Spacing.extraLarge)
    }

    @ViewBuilder
    private func authenticated(_ user: AuthUser) -> some View {
        if viewModel.user?.id != user.id { loading("Loading your profile…") }
        else {
            switch viewModel.state {
            case .idle, .loading: loading("Loading your profile…")
            case .error(let message):
                VStack(spacing: AppTheme.Spacing.large) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark").font(AppTheme.Typography.title).accessibilityHidden(true)
                    Text("Unable to load your profile").font(AppTheme.Typography.headline)
                    Text(message).foregroundStyle(AppTheme.secondary).multilineTextAlignment(.center)
                    SecondaryButton(title: "Retry", systemImage: "arrow.clockwise") {
                        Task { await viewModel.load(user: auth.state.user) }
                    }
                }
                .padding(AppTheme.Spacing.extraLarge)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
            case .loaded(let profile):
                VStack(spacing: AppTheme.Spacing.medium) {
                    ProfileAvatar(name: profile.displayName)
                    Text(profile.displayName ?? "Your profile")
                        .font(AppTheme.Typography.title).accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("profile-display-name")
                    Text(user.email).font(AppTheme.Typography.secondary).foregroundStyle(AppTheme.secondary)
                        .textSelection(.enabled).accessibilityIdentifier("profile-email")
                    Button { path.append(.edit) } label: {
                        Label("Edit Profile", systemImage: "pencil").font(AppTheme.Typography.button)
                            .padding(.horizontal, AppTheme.Spacing.extraLarge)
                            .frame(minHeight: AppTheme.Metrics.minimumTapTarget)
                            .background(AppTheme.surface, in: Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("profile-edit")
                }
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity).padding(.vertical, AppTheme.Spacing.large)
            }
            menu("MY ACTIVITY", destinations: [.saved, .reviews, .submissions, .reports])
            menu("SETTINGS", destinations: [.account, .privacy, .help])
            VStack(spacing: AppTheme.Spacing.small) {
                Button(role: .destructive) { confirmLogout = true } label: {
                    HStack {
                        if auth.isBusy { ProgressView() }
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }.frame(maxWidth: .infinity, minHeight: AppTheme.Metrics.minimumTapTarget)
                }
                .font(AppTheme.Typography.button).foregroundStyle(AppTheme.foreground).disabled(auth.isBusy)
                .accessibilityLabel("Log out of RestRoom Finder").accessibilityIdentifier("profile-logout")
                Text("Signs out this device only.").font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                if let message = auth.message { Text(message).font(AppTheme.Typography.caption) }
            }
        }
    }

    private func menu(_ title: String, destinations: [Destination]) -> some View {
        ProfileSectionCard(title: title) {
            ForEach(destinations, id: \.self) { destination in
                NavigationLink(value: destination) { ProfileMenuRow(title: destination.rawValue, symbol: destination.symbol) }
                    .buttonStyle(.plain).accessibilityHint(destination == .saved ? "Opens your saved restrooms" : destination == .reviews ? "Opens your restroom reviews" : destination == .submissions ? "Opens your private restroom submissions" : destination == .reports ? "Opens your private reports" : "Opens a placeholder for a future feature")
                if destination != destinations.last { Divider().padding(.horizontal, AppTheme.Spacing.large) }
            }
        }
    }

    private func loading(_ title: String) -> some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            ProgressView()
            Text(title).font(AppTheme.Typography.secondary).foregroundStyle(AppTheme.secondary)
            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.extraLarge)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
        .accessibilityElement(children: .combine)
    }
}
