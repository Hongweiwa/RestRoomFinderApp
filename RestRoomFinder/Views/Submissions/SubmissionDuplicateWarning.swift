import SwiftUI

struct SubmissionDuplicateWarning: View {
    let candidates: [SubmissionDuplicate]
    let checkFailed: Bool
    let onContinue: () -> Void
    let onCancel: () -> Void
    @State private var viewing: SubmissionDuplicate?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading,spacing: AppTheme.Spacing.large) {
                    Text(checkFailed ? "Duplicate Check Unavailable" : "Possible Existing Restroom").font(AppTheme.Typography.title)
                    Text(checkFailed ? "We couldn't finish checking for nearby duplicates. You can try again later or submit anyway for review." : "A restroom or your pending submission may already exist near this location. Nearby facilities can still be separate restrooms.")
                        .foregroundStyle(AppTheme.secondary)
                    ForEach(candidates) { candidate in
                        VStack(alignment: .leading,spacing: AppTheme.Spacing.small) {
                            Text(candidate.name ?? "Nearby restroom").font(AppTheme.Typography.headline)
                            Text("\(candidate.distanceMeters.formatted(.number.precision(.fractionLength(0)))) m from the selected location · \(candidate.kind == .submission ? "Your pending submission" : "Existing restroom")")
                                .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                            if candidate.googlePlaceID != nil { Text("Google Maps").font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary) }
                            Button("View Existing") { viewing = candidate }.frame(minHeight: AppTheme.Metrics.minimumTapTarget)
                        }.padding(AppTheme.Spacing.large).frame(maxWidth: .infinity,alignment: .leading)
                            .background(AppTheme.surface,in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
                    }
                    PrimaryButton(title: "Submit Anyway",action: onContinue).accessibilityIdentifier("submit-anyway")
                    SecondaryButton(title: "Cancel",action: onCancel)
                }.padding(AppTheme.Spacing.extraLarge)
            }.appScreenStyle().navigationTitle("Review Location").navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $viewing) { candidate in
            NavigationStack {
                Group {
                    if let restroom = candidate.restroom { RestroomDetailView(restroom: restroom) }
                    else { SubmissionLookupView(id: candidate.id) }
                }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { viewing = nil } } }
            }
        }
    }
}

private struct SubmissionLookupView: View {
    let id: UUID
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var submissions: MySubmissionsViewModel
    @State private var record: RestroomSubmission?
    @State private var error: String?
    var body: some View {
        Group {
            if let record, record.userID == auth.state.user?.id { SubmissionDetailView(submission: record) }
            else if let error { ContentUnavailableView("Submission unavailable",systemImage: "exclamationmark.circle",description: Text(error)) }
            else { ProgressView("Loading submission…") }
        }.appScreenStyle()
        .task(id: auth.state.user?.id) {
            record = nil; error = nil
            guard let user = auth.state.user else { return }
            do {
                let result = try await submissions.detail(id: id,user: user)
                if auth.state.user?.id == user.id { record = result }
            } catch { self.error = AddRestroomViewModel.message(error) }
        }
    }
}
