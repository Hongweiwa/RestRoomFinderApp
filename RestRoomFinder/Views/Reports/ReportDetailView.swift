import SwiftUI

struct ReportDetailView: View {
    let reportID: UUID
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var reports: MyReportsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var report: RestroomReport?
    @State private var error: String?
    @State private var request = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: AppTheme.Spacing.extraLarge) {
                if let user = auth.state.user {
                    if let report, report.userID == user.id, reports.userID == user.id { content(report) }
                    else if let error {
                        ContentUnavailableView("Unable to load report",systemImage: "wifi.exclamationmark",description: Text(error))
                        SecondaryButton(title: "Retry") { Task { await load() } }
                    } else { ProgressView("Loading report…") }
                } else {
                    ContentUnavailableView("Sign In Required",systemImage: "lock",description: Text("Your reports are private to your account."))
                }
            }.padding(AppTheme.Spacing.extraLarge).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.appScreenStyle().navigationTitle("Report Details").navigationBarTitleDisplayMode(.inline)
            .task(id: auth.state.user?.id) { await load() }
            .refreshable { await load() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
            .onDisappear { request += 1; report = nil }
    }
    private func content(_ report: RestroomReport) -> some View {
        VStack(alignment: .leading,spacing: AppTheme.Spacing.extraLarge) {
            field("Restroom",reports.label(for: report))
            if let address = report.restroom?.address { field("Address",address) }
            if let url = report.googleMapsURL {
                Link("View reported place in Google Maps",destination: url).font(AppTheme.Typography.body)
                    .frame(minHeight: AppTheme.Metrics.minimumTapTarget).accessibilityHint("Opens the external listing for this report")
            }
            field("Issue",report.type.title)
            if let details = report.details { field("Description",details) }
            field("Submitted",report.createdAt.formatted(date: .long,time: .shortened))
            ReportStatusBadge(status: report.status)
            Text(report.status.explanation).font(AppTheme.Typography.body)
            if let date = report.reviewedAt { field("Reviewed",date.formatted(date: .long,time: .shortened)) }
            if let date = report.resolvedAt { field("Resolved",date.formatted(date: .long,time: .shortened)) }
            Text("A report is an unverified claim. Submitting it does not automatically change published restroom information.")
                .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
        }
    }
    private func field(_ title: String,_ value: String) -> some View {
        VStack(alignment: .leading,spacing: AppTheme.Spacing.small) {
            Text(title).font(AppTheme.Typography.caption).foregroundStyle(AppTheme.secondary)
            Text(value).font(AppTheme.Typography.body).textSelection(.enabled)
        }
    }
    private func load() async {
        request += 1; let ticket = request
        report = nil; error = nil
        guard let user = auth.state.user else { return }
        do {
            let result = try await reports.detail(id: reportID,user: user)
            guard ticket == request, auth.state.user?.id == user.id, !Task.isCancelled else { return }
            report = result
        } catch {
            guard ticket == request, auth.state.user?.id == user.id, !Task.isCancelled else { return }
            self.error = ReportFailure.message(error)
        }
    }
}
