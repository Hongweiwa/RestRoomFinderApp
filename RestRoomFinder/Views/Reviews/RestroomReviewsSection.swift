import SwiftUI

struct RestroomReviewsSection: View {
    let restroom: Restroom
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var reviews: ReviewsViewModel
    @State private var showAuthPrompt = false
    @State private var authPage: AuthenticationView.Page?
    @State private var editor: Editor?
    @State private var deleting: RestroomReview?
    @State private var error: String?
    @State private var checking = false
    private struct Editor: Identifiable { let id = UUID(); let review: RestroomReview?; let userID: UUID }
    private var entry: ReviewsViewModel.Entry { reviews.entry(for: restroom) }
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            SectionHeader(title: "RestRoom Finder Reviews")
            Button(entry.own == nil ? "Write a Review" : "Edit Your Review") {
                guard !checking else { return }
                checking = true
                Task {
                    defer { checking = false }
                    guard await auth.requireAuthentication(), let user = auth.state.user else { showAuthPrompt = true; return }
                    reviews.setUser(user)
                    await reviews.load(restroom)
                    guard auth.state.user?.id == user.id else { return }
                    guard reviews.entry(for: restroom).state == .loaded else {
                        error = "Unable to check your existing review. Retry loading before writing."; return
                    }
                    editor = Editor(review: reviews.entry(for: restroom).own, userID: user.id)
                }
            }
            .buttonStyle(AppButtonStyle(isPrimary: true))
            .disabled(reviews.isSaving || checking)
            .accessibilityIdentifier("write-review")
            switch entry.state {
            case .idle, .loading: ProgressView("Loading reviews…")
            case .error(let message):
                Text("Unable to load reviews.").font(AppTheme.Typography.headline)
                Text(message).font(AppTheme.Typography.caption)
                Button("Retry") { Task { await reviews.load(restroom) } }.frame(minHeight: 44)
            case .loaded:
                Text("\(reviews.summaries[restroom.reviewKey]?.countDescription ?? "0 restroom reviews") · Newest first")
                    .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                if entry.rows.isEmpty { Text("No Reviews Yet. Be the first to share your experience.").foregroundStyle(AppTheme.secondary) }
                ForEach(entry.rows) { review in
                    ReviewRow(review: review, isOwn: review.userID != nil && review.userID == auth.state.user?.id)
                }
                if let own = entry.own, own.userID == auth.state.user?.id {
                    Button("Delete Your Review", role: .destructive) { deleting = own }
                        .foregroundStyle(AppTheme.foreground).frame(minHeight: 44).disabled(reviews.isSaving)
                }
                if let message = entry.pageError { Text(message).font(AppTheme.Typography.caption) }
                if entry.hasMore {
                    SecondaryButton(title: entry.paging ? "Loading…" : "Load More") { Task { await reviews.loadMore(restroom) } }
                        .disabled(entry.paging)
                }
            }
        }
        .confirmationDialog("Sign in to review this restroom.", isPresented: $showAuthPrompt, titleVisibility: .visible) {
            Button("Create Account") { authPage = .signup }
            Button("Log In") { authPage = .login }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $authPage) { AuthenticationView(viewModel: auth, initialPage: $0) }
        .sheet(item: $editor) { ReviewEditorView(restroom: restroom, existing: $0.review, userID: $0.userID) }
        .confirmationDialog("Delete Review?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let review = deleting, let user = auth.state.user {
                    Task { error = await reviews.delete(review, expectedUserID: user.id) }
                }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("This review will be permanently removed.") }
        .alert("Reviews", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
        .onChange(of: auth.state.user?.id) { _, _ in editor = nil; deleting = nil; error = nil }
    }
}
