import SwiftUI

struct MyReportsView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var reports: MyReportsViewModel
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: AppTheme.Spacing.large) {
                if let user = auth.state.user, reports.userID == user.id { content(user) }
                else {
                    ContentUnavailableView("Your Reports",systemImage: "exclamationmark.bubble",
                        description: Text("Sign in to view your private reports."))
                }
            }.padding(AppTheme.Spacing.extraLarge).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.appScreenStyle().navigationTitle("My Reports").navigationBarTitleDisplayMode(.inline)
            .task(id: "\(auth.state.user?.id.uuidString ?? "guest"):\(reports.changeRevision)") { await reports.load(user: auth.state.user) }
            .refreshable { await reports.load(user: auth.state.user) }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await reports.load(user: auth.state.user) } } }
    }
    @ViewBuilder private func content(_ user: AuthUser) -> some View {
        switch reports.state {
        case .idle,.loading: ProgressView("Loading your reports…")
        case .error(let message):
            ContentUnavailableView("Unable to load reports",systemImage: "wifi.exclamationmark",description: Text(message))
            SecondaryButton(title: "Retry") { Task { await reports.load(user: user) } }
        case .loaded:
            if reports.records.isEmpty {
                ContentUnavailableView("No Reports Yet",systemImage: "exclamationmark.bubble",
                    description: Text("Reports you submit about restroom information will appear here."))
            }
            ForEach(reports.records) { report in
                NavigationLink { ReportDetailView(reportID: report.id) } label: {
                    VStack(alignment: .leading,spacing: AppTheme.Spacing.medium) {
                        HStack {
                            Text(reports.label(for: report)).font(AppTheme.Typography.headline)
                            Spacer(minLength: AppTheme.Spacing.small)
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }
                        Text(report.type.title).font(AppTheme.Typography.body)
                        ReportStatusBadge(status: report.status)
                        Text("Submitted \(report.createdAt.formatted(date: .abbreviated,time: .omitted))")
                            .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
                    }.padding(AppTheme.Spacing.large).frame(maxWidth: .infinity,alignment: .leading)
                        .background(AppTheme.surface,in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))
                }.buttonStyle(.plain).accessibilityHint("Opens your private report details")
            }
            if let message = reports.pageError { Text(message).font(AppTheme.Typography.caption) }
            if reports.hasMore {
                SecondaryButton(title: reports.paging ? "Loading…" : "Load More") { Task { await reports.load(user: user,more: true) } }
                    .disabled(reports.paging)
            }
        }
    }
}
