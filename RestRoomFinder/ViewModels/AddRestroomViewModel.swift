import Combine
import Foundation

@MainActor
final class AddRestroomViewModel: ObservableObject {
    enum State: Equatable {
        case idle,locating,checking,submitting
        case warning([SubmissionDuplicate],checkFailed: Bool)
        case success(RestroomSubmission)
        case error(String)
    }
    @Published var draft: SubmissionDraft
    @Published private(set) var state: State = .idle
    let userID: UUID
    let existing: RestroomSubmission?
    let requestID: UUID
    private let service: any RestroomSubmissionServicing
    private var generation = 0
    private var confirmedDraft: SubmissionDraft?
    var isBusy: Bool { state == .checking || state == .submitting }
    var isLocked: Bool {
        if isBusy { return true }
        if case .warning = state { return true }
        if case .success = state { return true }
        return false
    }
    init(service: any RestroomSubmissionServicing,userID: UUID,existing: RestroomSubmission? = nil,requestID: UUID = UUID()) {
        self.service = service; self.userID = userID; self.existing = existing
        self.requestID = existing?.clientRequestID ?? requestID; draft = SubmissionDraft(submission: existing)
    }
    func choose(_ coordinate: SubmissionCoordinate) {
        guard !isLocked, coordinate.isValid else { return }
        draft.coordinate = coordinate; state = .idle
    }
    func requestLocation() { guard !isLocked else { return }; state = .locating }
    func locationUnavailable(_ message: String) { guard state == .locating else { return }; state = .error(message) }
    func cancel() { generation += 1; confirmedDraft = nil; state = .idle }
    func submit(knownRestrooms: [Restroom]) async {
        guard !isLocked else { return }
        guard existing == nil || existing?.status == .pending else { state = .error(SubmissionFailure.noLongerPending.localizedDescription); return }
        if let error = draft.validationError { state = .error(error); return }
        guard let coordinate = draft.coordinate else { return }
        let snapshot = draft, request = generation
        state = .checking
        let local = SubmissionDuplicate.nearby(knownRestrooms,coordinate: coordinate)
        do {
            let remote = try await service.duplicates(coordinate: coordinate,requestID: requestID,editingID: existing?.id,userID: userID)
            guard generation == request, !Task.isCancelled else { return }
            var seen = Set<String>()
            let warnings = (local+remote).sorted { $0.distanceMeters < $1.distanceMeters }.filter { seen.insert($0.key).inserted }
            if !warnings.isEmpty { confirmedDraft = snapshot; state = .warning(Array(warnings.prefix(10)),checkFailed: false); return }
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            if case SubmissionFailure.sessionChanged = error { state = .error(SubmissionFailure.sessionChanged.localizedDescription); return }
            // A failed check is never presented as proof that no duplicate exists.
            confirmedDraft = snapshot
            state = .warning(local,checkFailed: true)
            return
        }
        await persist(snapshot,generation: request)
    }
    func submitAnyway() async {
        guard case .warning = state, let snapshot = confirmedDraft else { return }
        confirmedDraft = nil
        await persist(snapshot,generation: generation)
    }
    func cancelWarning() { guard case .warning = state else { return }; confirmedDraft = nil; state = .idle }
    private func persist(_ snapshot: SubmissionDraft,generation request: Int) async {
        state = .submitting
        do {
            let saved = try await service.save(snapshot,requestID: requestID,existing: existing,userID: userID)
            guard generation == request, !Task.isCancelled else { return }
            guard saved.userID == userID else { state = .error(SubmissionFailure.sessionChanged.localizedDescription); return }
            state = .success(saved)
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            state = .error(Self.message(error))
        }
    }
    static func message(_ error: Error) -> String { (error as? SubmissionFailure)?.localizedDescription ?? SubmissionFailure.unavailable.localizedDescription }
}
