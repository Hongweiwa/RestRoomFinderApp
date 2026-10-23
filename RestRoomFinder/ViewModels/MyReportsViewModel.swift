import Combine
import Foundation

@MainActor
final class MyReportsViewModel: ObservableObject {
    enum State: Equatable { case idle,loading,loaded,error(String) }
    @Published private(set) var records: [RestroomReport] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var userID: UUID?
    @Published private(set) var hasMore = false
    @Published private(set) var paging = false
    @Published private(set) var pageError: String?
    @Published private(set) var changeRevision = 0
    let service: any ReportServicing
    private var generation = 0
    private var request = 0
    // Only transient labels, never copied Google content in the reports table.
    private var labels: [UUID: String] = [:]
    init(service: any ReportServicing) { self.service = service }
    func setUser(_ user: AuthUser?) {
        guard userID != user?.id else { return }
        generation += 1; request += 1; userID = user?.id; records = []; labels = [:]
        state = .idle; hasMore = false; paging = false; pageError = nil; changeRevision += 1
    }
    func label(for report: RestroomReport) -> String { report.restroom?.name ?? labels[report.restroomID] ?? report.restroomLabel }
    func didSubmit(_ report: RestroomReport,restroom: Restroom) {
        guard let userID, report.userID == userID else { return }
        request += 1; paging = false; pageError = nil
        labels[report.restroomID] = restroom.name
        records.removeAll { $0.id == report.id }; records.insert(report,at: 0)
        changeRevision += 1
    }
    func detail(id: UUID,user: AuthUser) async throws -> RestroomReport {
        guard userID == user.id else { throw ReportFailure.sessionChanged }
        let account = generation
        let report = try await service.fetchReport(id: id,userID: user.id)
        guard account == generation, userID == user.id, report.userID == user.id else { throw ReportFailure.sessionChanged }
        return report
    }
    func load(user: AuthUser?,more: Bool = false) async {
        setUser(user)
        guard let user, !paging else { return }
        if more && (state != .loaded || !hasMore) { return }
        request += 1
        let ticket = request, account = generation
        if more { paging = true; pageError = nil } else { state = .loading }
        do {
            let rows = try await service.fetchMyReports(userID: user.id,offset: more ? records.count : 0)
            guard request == ticket, generation == account, !Task.isCancelled else { return }
            guard rows.allSatisfy({ $0.userID == user.id }) else { throw ReportFailure.sessionChanged }
            let visible = Array(rows.prefix(20)), seen = Set(records.map(\.id))
            records = more ? records+visible.filter { !seen.contains($0.id) } : visible
            hasMore = rows.count > 20; state = .loaded
        } catch {
            guard request == ticket, generation == account, !Task.isCancelled else { return }
            if more { pageError = ReportFailure.message(error) } else { state = .error(ReportFailure.message(error)) }
        }
        if request == ticket, generation == account { paging = false }
    }
}
