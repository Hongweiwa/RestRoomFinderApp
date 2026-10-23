import SwiftUI

struct MyReviewsView: View {
    let onExplore: () -> Void
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var reviews: ReviewsViewModel
    @State private var editing: RestroomReview?
    @State private var deleting: RestroomReview?
    @State private var selected: SavedPlaceDetails?
    @State private var opening: UUID?
    @State private var error: String?
    @State private var authPage: AuthenticationView.Page?
    private var loadKey: String { "\(auth.state.user?.id.uuidString ?? "guest"):\(reviews.changeRevision)" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                if let user = auth.state.user, reviews.userID == user.id {
                    content(user)
                } else {
                    ContentUnavailableView("Your reviews", systemImage: "star", description: Text("Sign in to manage your restroom reviews."))
                    PrimaryButton(title: "Create Account") { authPage = .signup }
                    SecondaryButton(title: "Log In") { authPage = .login }
                }
            }.padding(AppTheme.Spacing.extraLarge)
        }
        .navigationTitle("My Reviews").navigationBarTitleDisplayMode(.inline).appScreenStyle()
        .task(id: loadKey) { reviews.setUser(auth.state.user); await reviews.loadMine() }
        .refreshable { await reviews.loadMine() }
        .sheet(item: $authPage) { AuthenticationView(viewModel: auth, initialPage: $0) }
        .sheet(item: $editing) { review in
            if let user = auth.state.user, user.id == review.userID {
                ReviewEditorView(restroom: nil, existing: review, userID: user.id)
            }
        }
        .navigationDestination(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let selected { RestroomDetailView(restroom: selected.restroom, placeAttributions: selected.attributions) }
        }
        .confirmationDialog("Delete Review?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let review = deleting, let user = auth.state.user {
                    Task { error = await reviews.delete(review, expectedUserID: user.id) }
                }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("This review will be permanently removed.") }
        .alert("My Reviews", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
        .onChange(of: auth.state.user?.id) { _, _ in editing = nil; deleting = nil; selected = nil; opening = nil; error = nil }
    }
    @ViewBuilder private func content(_ user: AuthUser) -> some View {
        switch reviews.myState {
        case .idle, .loading: ProgressView("Loading your reviews…")
        case .error(let message):
            ContentUnavailableView("Unable to load reviews", systemImage: "wifi.exclamationmark", description: Text(message))
            SecondaryButton(title: "Retry") { Task { await reviews.loadMine() } }
        case .loaded:
            if reviews.myRows.isEmpty {
                ContentUnavailableView("No Reviews Yet", systemImage: "star", description: Text("Reviews you write about restrooms will appear here."))
                PrimaryButton(title: "Explore Restrooms", action: onExplore)
            }
            ForEach(reviews.myRows) { row in
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Button {
                        opening = row.id
                        Task {
                            defer { opening = nil }
                            do { selected = try await reviews.openPlace(for: row) }
                            catch { self.error = "Place information is unavailable. You can still edit or delete your review." }
                        }
                    } label: {
                        HStack {
                            Text(reviews.place(for: row)?.restroom.name ?? row.restroom?.name ?? "Reviewed restroom")
                            Spacer()
                            if opening == row.id { ProgressView() } else { Image(systemName: "chevron.right") }
                        }.font(AppTheme.Typography.headline).frame(minHeight: 44)
                    }.disabled(opening != nil || row.restroom == nil)
                    if row.restroom?.googlePlaceID != nil, reviews.place(for: row) == nil {
                        Text("Open to load current place information.").font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                    }
                    if let place = reviews.place(for: row), place.restroom.googlePlaceID != nil {
                        Text("Google Maps").font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                        if let attribution = place.attributions { Text(AttributedString(attribution)).font(AppTheme.Typography.caption) }
                    }
                    ReviewRow(review: row.review, isOwn: true)
                    HStack {
                        Button("Edit") { editing = row.review }.frame(minHeight: 44)
                        Spacer()
                        Button("Delete", role: .destructive) { deleting = row.review }.frame(minHeight: 44)
                    }.disabled(reviews.isSaving).foregroundStyle(AppTheme.foreground)
                }
            }
            if let message = reviews.myPageError { Text(message).font(AppTheme.Typography.caption) }
            if reviews.myHasMore {
                SecondaryButton(title: reviews.myPaging ? "Loading…" : "Load More") { Task { await reviews.loadMine(more: true) } }
                    .disabled(reviews.myPaging)
            }
        }
    }
}
