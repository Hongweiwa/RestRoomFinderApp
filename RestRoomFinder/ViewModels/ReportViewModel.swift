import Combine
import Foundation

@MainActor
final class ReportViewModel: ObservableObject {
    enum State: Equatable { case idle,submitting,success(RestroomReport),error(String) }
    @Published var draft = ReportDraft()
    @Published private(set) var state: State = .idle
    let restroom: Restroom
    let userID: UUID
    let requestID = UUID()
    private let service: any ReportServicing
    private var generation = 0
    var isBusy: Bool { state == .submitting }
    var isLocked: Bool { if case .success = state { return true }; return isBusy }
    init(service: any ReportServicing,restroom: Restroom,userID: UUID) {
        self.service = service; self.restroom = restroom; self.userID = userID
    }
    func submit() async {
        guard !isLocked else { return }
        if let error = draft.validationError { state = .error(error); return }
        let ticket = generation, submittedDraft = draft
        state = .submitting
        do {
            let row = try await service.submit(submittedDraft,restroom: restroom,requestID: requestID,userID: userID)
            guard ticket == generation, !Task.isCancelled else { return }
            guard row.userID == userID else { state = .error(ReportFailure.message(ReportFailure.sessionChanged)); return }
            state = .success(row)
        } catch {
            guard ticket == generation, !Task.isCancelled else { return }
            state = .error(ReportFailure.message(error))
        }
    }
    func cancel() { generation += 1; state = .idle }
}
