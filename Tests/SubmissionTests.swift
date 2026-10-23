import CoreLocation
import Foundation

@MainActor
private final class SubmissionTestService: RestroomSubmissionServicing {
    var rows: [RestroomSubmission] = []
    var candidates: [SubmissionDuplicate] = []
    var checks = 0; var writes = 0; var fetches = 0
    var failCheck = false; var failSave = false; var failFetch = false
    var suspendSave = false; var suspendFetch = false
    var savedRequests: [UUID] = []
    var saveContinuation: CheckedContinuation<RestroomSubmission, Error>?
    var fetchContinuation: CheckedContinuation<[RestroomSubmission], Error>?
    func fetch(userID: UUID,offset: Int) async throws -> [RestroomSubmission] {
        fetches += 1
        if suspendFetch { return try await withCheckedThrowingContinuation { fetchContinuation = $0 } }
        if failFetch { throw SubmissionFailure.unavailable }
        return Array(rows.filter { $0.userID == userID }.dropFirst(offset).prefix(21))
    }
    func fetch(id: UUID,userID: UUID) async throws -> RestroomSubmission {
        guard let row = rows.first(where: { $0.id == id && $0.userID == userID }) else { throw SubmissionFailure.unavailable }
        return row
    }
    func duplicates(coordinate: SubmissionCoordinate,requestID: UUID,editingID: UUID?,userID: UUID) async throws -> [SubmissionDuplicate] {
        checks += 1
        if failCheck { throw SubmissionFailure.unavailable }
        return candidates
    }
    func save(_ draft: SubmissionDraft,requestID: UUID,existing: RestroomSubmission?,userID: UUID) async throws -> RestroomSubmission {
        writes += 1; savedRequests.append(requestID)
        if suspendSave { return try await withCheckedThrowingContinuation { saveContinuation = $0 } }
        if failSave { throw SubmissionFailure.unavailable }
        let result = Self.record(userID,draft: draft,requestID: requestID,id: existing?.id ?? UUID())
        rows.removeAll { $0.id == result.id }; rows.append(result); return result
    }
    static func record(_ user: UUID,draft: SubmissionDraft,requestID: UUID = UUID(),id: UUID = UUID(),status: SubmissionStatus = .pending) -> RestroomSubmission {
        RestroomSubmission(id: id,userID: user,name: SubmissionDraft.trimmed(draft.name),address: SubmissionDraft.optional(draft.address),
            latitude: draft.coordinate!.latitude,longitude: draft.coordinate!.longitude,accessible: draft.accessible.value,
            babyChanging: draft.babyChanging.value,genderNeutral: draft.genderNeutral.value,free: draft.free.value,
            family: draft.family.value,allDay: draft.allDay.value,notes: SubmissionDraft.optional(draft.notes),status: status,
            createdAt: Date(),updatedAt: Date(),clientRequestID: requestID,approvedRestroomID: nil,rejectionReason: nil)
    }
}

@MainActor
enum SubmissionTests {
    static func run() async {
        let a = AuthUser(id: UUID(),email: "a@example.com"),b = AuthUser(id: UUID(),email: "b@example.com")
        let service = SubmissionTestService()
        let vm = AddRestroomViewModel(service: service,userID: a.id)
        await vm.submit(knownRestrooms: [])
        precondition(service.checks == 0 && service.writes == 0)
        vm.draft.name = "Test restroom"
        await vm.submit(knownRestrooms: [])
        precondition(service.checks == 0 && service.writes == 0)
        vm.draft.coordinate = .init(latitude: .nan,longitude: 0)
        await vm.submit(knownRestrooms: [])
        precondition(service.checks == 0)
        vm.draft.coordinate = .init(latitude: 91,longitude: 0)
        precondition(vm.draft.validationError != nil)
        vm.draft.coordinate = .init(latitude: 40,longitude: -73)
        vm.draft.notes = String(repeating: "x",count: 1001)
        await vm.submit(knownRestrooms: []); precondition(service.checks == 0)
        vm.draft.notes = " \n \t "
        vm.draft.address = " "
        await vm.submit(knownRestrooms: [])
        guard case .success(let saved) = vm.state else { preconditionFailure("Valid submission must succeed") }
        precondition(saved.status == .pending && saved.accessible == nil && saved.babyChanging == nil && saved.free == nil && saved.family == nil && saved.allDay == nil && saved.genderNeutral == nil)
        precondition(saved.notes == nil && saved.address == nil && saved.approvedRestroomID == nil)
        print("PASS: submission name/coordinate/notes validation makes no invalid requests; unknown features and blank text remain NULL; success is pending")
        let now = Date()
        let stale = CLLocation(coordinate: .init(latitude: 40,longitude: -73),altitude: 0,horizontalAccuracy: 10,verticalAccuracy: 0,timestamp: now.addingTimeInterval(-120))
        let fresh = CLLocation(coordinate: stale.coordinate,altitude: 0,horizontalAccuracy: 100,verticalAccuracy: 0,timestamp: now)
        precondition(SubmissionCoordinate.current(stale,now: now) == nil && SubmissionCoordinate.current(nil) == nil)
        precondition(SubmissionCoordinate.current(fresh,now: now)?.isValid == true)
        var draft = SubmissionDraft(); draft.name = "Different restroom name"; draft.coordinate = .init(latitude: 40,longitude: -73)
        var nearby = SampleRestrooms.all[0]
        nearby = Restroom(id: nearby.id,name: "Nearby restroom",latitude: 40.00001,longitude: -73,address: "Known",cleanlinessRating: nil,overallRating: nil,reviewCount: nil,distance: nil,openingHours: nil,accessibility: nil,babyChangingStation: nil,genderNeutral: nil,free: nil,imageName: "toilet")
        let duplicates = AddRestroomViewModel(service: service,userID: a.id)
        duplicates.draft = draft
        await duplicates.submit(knownRestrooms: [nearby])
        guard case .warning(let candidates,false) = duplicates.state else { preconditionFailure("Near coordinate requires warning") }
        precondition(candidates.count == 1 && candidates[0].restroom?.id == nearby.id && service.writes == 1)
        duplicates.cancelWarning(); precondition(duplicates.state == .idle)
        await duplicates.submit(knownRestrooms: [nearby]); await duplicates.submitAnyway()
        guard case .success = duplicates.state else { preconditionFailure("Fuzzy warning must allow Submit Anyway") }
        let checkFailure = AddRestroomViewModel(service: service,userID: a.id); checkFailure.draft = draft
        service.failCheck = true
        await checkFailure.submit(knownRestrooms: [])
        guard case .warning(_,true) = checkFailure.state else { preconditionFailure("Check failure cannot mean no duplicates") }
        service.failCheck = false
        print("PASS: fresh location checks, distance-based duplicate warning, cancel/override and explicit duplicate-check failure")
        let retry = AddRestroomViewModel(service: service,userID: a.id); retry.draft = draft
        service.failSave = true
        await retry.submit(knownRestrooms: [])
        guard case .error = retry.state else { preconditionFailure("Failed save must not succeed") }
        service.failSave = false
        await retry.submit(knownRestrooms: [])
        precondition(service.savedRequests.suffix(2).allSatisfy { $0 == retry.requestID })
        let busy = AddRestroomViewModel(service: service,userID: a.id); busy.draft = draft
        service.suspendSave = true
        let task = Task { await busy.submit(knownRestrooms: []) }
        for _ in 0..<1000 { if service.saveContinuation != nil { break }; await Task.yield() }
        precondition(service.saveContinuation != nil)
        let writeCount = service.writes
        await busy.submit(knownRestrooms: []); precondition(service.writes == writeCount)
        busy.cancel()
        service.saveContinuation?.resume(returning: saved); await task.value
        precondition(busy.state == .idle)
        service.suspendSave = false
        let edit = AddRestroomViewModel(service: service,userID: a.id,existing: saved)
        precondition(edit.draft.name == saved.name && edit.draft.accessible == .unknown)
        edit.draft.accessible = .no; edit.draft.free = .yes
        await edit.submit(knownRestrooms: [])
        guard case .success(let updated) = edit.state else { preconditionFailure("Pending edit should succeed") }
        precondition(updated.id == saved.id && updated.accessible == false && updated.free == true)
        let approved = SubmissionTestService.record(a.id,draft: draft,status: .approved)
        let locked = AddRestroomViewModel(service: service,userID: a.id,existing: approved)
        let before = service.writes
        await locked.submit(knownRestrooms: []); precondition(service.writes == before)
        print("PASS: retry reuses request identity, rapid taps blocked, cancelled/account-old save ignored, pending edit preserves ID, approved edit rejected")
        let store = MySubmissionsViewModel(service: service)
        service.rows = (0..<25).map { _ in SubmissionTestService.record(a.id,draft: draft) }
        await store.load(user: a)
        precondition(store.records.count == 20 && store.hasMore)
        await store.load(user: a,more: true)
        precondition(store.records.count == 25 && !store.hasMore)
        let reloaded = MySubmissionsViewModel(service: service)
        await reloaded.load(user: a); precondition(reloaded.records.count == 20)
        store.setUser(b); precondition(store.records.isEmpty)
        store.didSave(saved); precondition(store.records.isEmpty)
        await store.load(user: b); precondition(store.records.isEmpty && store.state == .loaded)
        service.suspendFetch = true
        let old = Task { await store.load(user: a) }
        for _ in 0..<1000 { if service.fetchContinuation != nil { break }; await Task.yield() }
        precondition(service.fetchContinuation != nil)
        store.setUser(b); service.suspendFetch = false
        await store.load(user: b)
        service.fetchContinuation?.resume(returning: [saved]); await old.value
        precondition(store.userID == b.id && store.records.isEmpty)
        service.failFetch = true
        await store.load(user: b)
        guard case .error = store.state else { preconditionFailure("Read error must not be empty success") }
        service.failFetch = false
        await store.load(user: b); precondition(store.state == .loaded)
        print("PASS: private submissions paging/reload, account clearing, stale A response isolation, error vs empty and retry")
    }
}
