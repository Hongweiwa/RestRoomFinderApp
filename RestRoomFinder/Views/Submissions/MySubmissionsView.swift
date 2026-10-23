import SwiftUI

struct MySubmissionsView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var submissions: MySubmissionsViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: AppTheme.Spacing.large) {
                AddRestroomButton()
                if let user = auth.state.user, submissions.userID == user.id {
                    content(user)
                } else {
                    ContentUnavailableView("Your Restroom Submissions",systemImage: "mappin.and.ellipse",
                        description: Text("Sign in to contribute a restroom and track its review status."))
                }
            }.padding(AppTheme.Spacing.extraLarge)
        }
        .appScreenStyle().navigationTitle("My Submissions").navigationBarTitleDisplayMode(.inline)
        .task(id: "\(auth.state.user?.id.uuidString ?? "guest"):\(submissions.changeRevision)") { await submissions.load(user: auth.state.user) }
        .refreshable { await submissions.load(user: auth.state.user) }
    }
    @ViewBuilder private func content(_ user: AuthUser) -> some View {
        switch submissions.state {
        case .idle,.loading: ProgressView("Loading your submissions…")
        case .error(let message):
            ContentUnavailableView("Unable to load submissions",systemImage: "wifi.exclamationmark",description: Text(message))
            SecondaryButton(title: "Retry") { Task { await submissions.load(user: user) } }
        case .loaded:
            if submissions.records.isEmpty {
                ContentUnavailableView("No Submissions Yet",systemImage: "mappin.and.ellipse",
                    description: Text("Restrooms you contribute will appear here while they are reviewed."))
            }
            ForEach(submissions.records) { record in
                NavigationLink { SubmissionDetailView(submission: record) } label: {
                    VStack(alignment: .leading,spacing: AppTheme.Spacing.medium) {
                        HStack {
                            Text(record.name).font(AppTheme.Typography.headline)
                            Spacer(minLength: AppTheme.Spacing.small)
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }
                        SubmissionStatusBadge(status: record.status)
                        Text("Submitted \(record.createdAt.formatted(date: .abbreviated,time: .omitted))")
                            .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                    }.padding(AppTheme.Spacing.large).frame(maxWidth: .infinity,alignment: .leading)
                        .background(AppTheme.surface,in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
                }.buttonStyle(.plain).accessibilityHint("Opens your private submission details")
            }
            if let error = submissions.pageError { Text(error).font(AppTheme.Typography.caption) }
            if submissions.hasMore {
                SecondaryButton(title: submissions.paging ? "Loading…" : "Load More") { Task { await submissions.load(user: user,more: true) } }
                    .disabled(submissions.paging)
            }
        }
    }
}
