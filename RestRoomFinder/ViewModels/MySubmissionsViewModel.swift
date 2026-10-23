import Combine
import Foundation

@MainActor
final class MySubmissionsViewModel: ObservableObject {
    enum State: Equatable { case idle,loading,loaded,error(String) }
    @Published private(set) var state: State = .idle
    @Published private(set) var records: [RestroomSubmission] = []
    @Published private(set) var userID: UUID?
    @Published private(set) var hasMore = false
    @Published private(set) var paging = false
    @Published private(set) var pageError: String?
    @Published private(set) var changeRevision = 0
    private var generation = 0
    private var request = 0
    private(set) var knownRestrooms: [Restroom] = []
    let service: any RestroomSubmissionServicing
    init(service: any RestroomSubmissionServicing) { self.service = service }
    func setUser(_ user: AuthUser?) {
        guard userID != user?.id else { return }
        generation += 1; request += 1; userID = user?.id; records = []
        state = .idle; hasMore = false; paging = false; pageError = nil; changeRevision += 1
    }
    func detail(id: UUID,user: AuthUser) async throws -> RestroomSubmission {
        guard userID == user.id else { throw SubmissionFailure.sessionChanged }
        let account = generation
        let record = try await service.fetch(id: id,userID: user.id)
        guard account == generation, userID == user.id, record.userID == user.id else { throw SubmissionFailure.sessionChanged }
        return record
    }
    func register(_ restrooms: [Restroom]) { knownRestrooms = restrooms }
    func didSave(_ submission: RestroomSubmission) {
        guard submission.userID == userID else { return }
        request += 1; paging = false; pageError = nil
        records.removeAll { $0.id == submission.id }; records.insert(submission,at: 0)
        changeRevision += 1
    }
    func load(user: AuthUser?,more: Bool = false) async {
        setUser(user)
        guard let user, !paging else { return }
        if more && (state != .loaded || !hasMore) { return }
        request += 1
        let ticket = request, account = generation
        if more { paging = true; pageError = nil } else { state = .loading }
        do {
            let rows = try await service.fetch(userID: user.id,offset: more ? records.count : 0)
            guard request == ticket, generation == account, !Task.isCancelled else { return }
            let visible = Array(rows.prefix(20)), seen = Set(records.map(\.id))
            records = more ? records+visible.filter { !seen.contains($0.id) } : visible
            hasMore = rows.count > 20; state = .loaded
        } catch {
            guard request == ticket, generation == account, !Task.isCancelled else { return }
            if more { pageError = AddRestroomViewModel.message(error) } else { state = .error(AddRestroomViewModel.message(error)) }
        }
        if request == ticket, generation == account { paging = false }
    }
}
