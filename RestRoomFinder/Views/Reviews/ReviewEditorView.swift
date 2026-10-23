import SwiftUI

struct ReviewEditorView: View {
    let restroom: Restroom?
    let existing: RestroomReview?
    let userID: UUID
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var reviews: ReviewsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ReviewDraft
    @State private var error: String?

    init(restroom: Restroom?, existing: RestroomReview?, userID: UUID) {
        self.restroom = restroom; self.existing = existing; self.userID = userID
        _draft = State(initialValue: ReviewDraft(review: existing))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.extraLarge) {
                    if let restroom { Text(restroom.name).font(AppTheme.Typography.title) }
                    Text("Rate the restroom itself. These scores are separate from Google place ratings.")
                        .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                    StarRatingControl(title: "Overall Restroom", rating: $draft.overallRating)
                    StarRatingControl(title: "Cleanliness", rating: $draft.cleanlinessRating)
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        Text("Share your experience (optional)").font(AppTheme.Typography.headline)
                        Text("Was it clean and easy to access? Please avoid personal information.")
                            .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                        TextEditor(text: $draft.comment)
                            .frame(minHeight: 140)
                            .padding(AppTheme.Spacing.small)
                            .scrollContentBackground(.hidden)
                            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
                            .accessibilityLabel("Review comment")
                        Text("\(draft.normalizedComment?.unicodeScalars.count ?? 0) / 1,000 characters")
                            .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                    }
                    if let validation = draft.validationError { Text(validation).font(AppTheme.Typography.caption) }
                    if let error { Text(error).font(AppTheme.Typography.caption).accessibilityIdentifier("review-error") }
                    PrimaryButton(title: reviews.isSaving ? "Saving…" : existing == nil ? "Submit Review" : "Save Changes") {
                        Task {
                            guard await auth.requireAuthentication(), auth.state.user?.id == userID else {
                                error = ReviewFailure.sessionChanged.localizedDescription; return
                            }
                            error = await reviews.submit(draft, restroom: restroom, existing: existing, expectedUserID: userID)
                            if error == nil { dismiss() }
                        }
                    }
                    .disabled(draft.validationError != nil || reviews.isSaving)
                    .accessibilityIdentifier("submit-review")
                }.padding(AppTheme.Spacing.extraLarge)
            }
            .scrollDismissesKeyboard(.interactively)
            .appScreenStyle()
            .navigationTitle(existing == nil ? "Write a Review" : "Edit Your Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(reviews.isSaving) } }
            .disabled(reviews.isSaving)
        }
        .interactiveDismissDisabled(reviews.isSaving)
        .onChange(of: auth.state.user?.id) { _, id in if id != userID { dismiss() } }
    }
}
