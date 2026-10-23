import SwiftUI

struct SubmissionDetailView: View {
    let submission: RestroomSubmission
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var submissions: MySubmissionsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var refreshed: RestroomSubmission?
    @State private var error: String?
    @State private var showEdit = false
    private var record: RestroomSubmission { refreshed ?? submission }
    var body: some View {
        ScrollView {
            if let userID = auth.state.user?.id, userID == record.userID {
                VStack(alignment: .leading,spacing: AppTheme.Spacing.extraLarge) {
                    Text(record.name).font(AppTheme.Typography.title)
                    SubmissionStatusBadge(status: record.status)
                    Text(record.status == .pending ? "Waiting for review. This submission is not on the public map." : record.status == .approved ? "Approved by moderation." : "This submission was not approved for publication.")
                        .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                    if let address = record.address { Text(address).textSelection(.enabled) }
                    Label(record.coordinate.description,systemImage: "mappin.and.ellipse").font(AppTheme.Typography.caption).monospacedDigit()
                    if GoogleMapsConfiguration.isConfigured, record.coordinate.isValid {
                        GoogleMapView(restrooms: [],location: nil,showsUserLocation: false,selectedRestroomID: nil,
                            initialCenter: record.coordinate.location,recenterRequest: 0,onSelect: { _ in },onCameraIdle: { _ in },isPreview: true)
                            .frame(height: AppTheme.Metrics.detailMapHeight)
                            .overlay { Image(systemName: "mappin").font(AppTheme.Typography.title).accessibilityHidden(true) }
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control))
                            .accessibilityLabel("Private submitted location")
                    }
                    VStack(alignment: .leading,spacing: AppTheme.Spacing.medium) {
                        SectionHeader(title: "Submitted Features")
                        feature("Wheelchair Accessibility",record.accessible)
                        feature("Baby Changing Station",record.babyChanging)
                        feature("Gender Neutral",record.genderNeutral)
                        feature("Free to Use",record.free)
                        feature("Family Restroom",record.family)
                        feature("Open 24 Hours",record.allDay)
                    }
                    if let notes = record.notes {
                        Text("Additional Notes").font(AppTheme.Typography.headline)
                        Text(notes).textSelection(.enabled)
                    }
                    Text("Submitted \(record.createdAt.formatted(date: .abbreviated,time: .omitted))")
                        .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                    if record.status == .rejected, let reason = record.rejectionReason {
                        Text("Reason").font(AppTheme.Typography.headline); Text(reason)
                    }
                    if record.status == .pending {
                        SecondaryButton(title: "Edit Pending Submission",systemImage: "pencil") { showEdit = true }
                    }
                    if let error { Text(error).font(AppTheme.Typography.caption) }
                }.padding(AppTheme.Spacing.extraLarge)
            } else { ContentUnavailableView("Submission unavailable",systemImage: "lock") }
        }.appScreenStyle().navigationTitle("Submission Details").navigationBarTitleDisplayMode(.inline)
        .task(id: auth.state.user?.id) { await refresh() }
        .refreshable { await refresh() }
        .sheet(isPresented: $showEdit) {
            if let user = auth.state.user, user.id == record.userID, record.status == .pending {
                AddRestroomView(service: submissions.service,userID: user.id,existing: record) { saved in
                    refreshed = saved; submissions.didSave(saved)
                }
            }
        }
        .onChange(of: auth.state.user?.id) { _, id in if id != record.userID { refreshed = nil; showEdit = false; dismiss() } }
    }
    private func feature(_ title: String,_ value: Bool?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { Text(title); Spacer(); Text(SubmissionFeature(value).rawValue).foregroundStyle(AppTheme.secondary) }
            VStack(alignment: .leading) { Text(title); Text(SubmissionFeature(value).rawValue).foregroundStyle(AppTheme.secondary) }
        }.font(AppTheme.Typography.secondary).accessibilityElement(children: .combine)
    }
    private func refresh() async {
        guard let user = auth.state.user, user.id == submission.userID else { return }
        do {
            let result = try await submissions.detail(id: submission.id,user: user)
            if auth.state.user?.id == user.id { refreshed = result; error = nil }
        } catch { self.error = AddRestroomViewModel.message(error) }
    }
}
