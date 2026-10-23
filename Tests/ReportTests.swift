import Foundation

@MainActor
private final class ReportTestService: ReportServicing {
    var rows: [RestroomReport] = []
    var writes = 0
    var requests: [UUID] = []
    var fail = false, suspendWrite = false, suspendRead = false
    var writeContinuation: CheckedContinuation<RestroomReport,Error>?
    var readContinuation: CheckedContinuation<[RestroomReport],Error>?
    func submit(_ draft: ReportDraft,restroom: Restroom,requestID: UUID,userID: UUID) async throws -> RestroomReport {
        writes += 1; requests.append(requestID)
        if suspendWrite { return try await withCheckedThrowingContinuation { writeContinuation = $0 } }
        if fail { throw ReportFailure.unavailable }
        let report = Self.record(userID,restroom: restroom,draft: draft,requestID: requestID)
        rows.append(report); return report
    }
    func fetchMyReports(userID: UUID,offset: Int) async throws -> [RestroomReport] {
        if suspendRead { return try await withCheckedThrowingContinuation { readContinuation = $0 } }
        if fail { throw ReportFailure.unavailable }
        return Array(rows.filter { $0.userID == userID }.dropFirst(offset).prefix(21))
    }
    func fetchReport(id: UUID,userID: UUID) async throws -> RestroomReport {
        guard let row = rows.first(where: { $0.id == id && $0.userID == userID }) else { throw ReportFailure.unavailable }
        return row
    }
    static func record(_ user: UUID,restroom: Restroom,draft: ReportDraft,requestID: UUID = UUID()) -> RestroomReport {
        .init(id: UUID(),userID: user,restroomID: restroom.id,type: draft.type!,details: draft.normalizedDetails,status: .pending,
            createdAt: Date(),updatedAt: Date(),reviewedAt: nil,resolvedAt: nil,clientRequestID: requestID,restroom: nil)
    }
}

@MainActor
enum ReportTests {
    static func run() async {
        let a = AuthUser(id: UUID(),email: "a@example.com"), b = AuthUser(id: UUID(),email: "b@example.com")
        let restroom = SampleRestrooms.all[0], service = ReportTestService()
        let form = ReportViewModel(service: service,restroom: restroom,userID: a.id)
        await form.submit(); precondition(service.writes == 0)
        form.draft.type = .other
        await form.submit(); precondition(service.writes == 0)
        form.draft.details = "   short  "
        await form.submit(); precondition(service.writes == 0)
        form.draft.details = String(repeating: "x",count: 1001)
        await form.submit(); precondition(service.writes == 0)
        form.draft = ReportDraft(type: .incorrectLocation,details: " \n \t ")
        await form.submit()
        guard case .success(let saved) = form.state else { preconditionFailure("Valid report should succeed") }
        precondition(saved.details == nil && saved.status == .pending && saved.restroomID == restroom.id)
        await form.submit(); precondition(service.writes == 1)
        precondition(ReportType.allCases.count == 9 && ReportStatus.allCases.count == 4)
        let google = RestroomReport(id: UUID(),userID: a.id,restroomID: UUID(),type: .incorrectLocation,details: nil,status: .pending,
            createdAt: Date(),updatedAt: Date(),reviewedAt: nil,resolvedAt: nil,clientRequestID: UUID(),
            restroom: .init(id: UUID(),googlePlaceID: "place+id&test",name: nil,address: nil,latitude: nil,longitude: nil,features: nil))
        precondition(google.restroomLabel == "Google Maps restroom")
        let url = URLComponents(url: google.googleMapsURL!,resolvingAgainstBaseURL: false)!
        precondition(url.host == "www.google.com" && url.queryItems?.first(where: { $0.name == "query_place_id" })?.value == "place+id&test")
        precondition(saved.googleMapsURL == nil)
        print("PASS: report type/Other/length validation makes no invalid requests, blank optional text becomes nil, confirmed pending success locks repeat submission")
        let retry = ReportViewModel(service: service,restroom: restroom,userID: a.id)
        retry.draft = ReportDraft(type: .other,details: "  Door requires a key.  ")
        service.fail = true
        await retry.submit()
        guard case .error = retry.state else { preconditionFailure("Network error must not succeed") }
        precondition(retry.draft.details == "  Door requires a key.  ")
        service.fail = false
        await retry.submit()
        precondition(service.requests.suffix(2).allSatisfy { $0 == retry.requestID })
        let busy = ReportViewModel(service: service,restroom: restroom,userID: a.id)
        busy.draft.type = .uncleanRestroom; service.suspendWrite = true
        let pending = Task { await busy.submit() }
        for _ in 0..<1000 { if service.writeContinuation != nil { break }; await Task.yield() }
        precondition(service.writeContinuation != nil)
        let count = service.writes
        await busy.submit(); precondition(service.writes == count)
        busy.cancel(); service.writeContinuation?.resume(returning: saved); await pending.value
        precondition(busy.state == .idle)
        service.suspendWrite = false
        print("PASS: report network failure retains draft; retry reuses request UUID; rapid taps blocked; cancelled/account-old write cannot publish success")
        let store = MyReportsViewModel(service: service)
        service.rows = (0..<25).map { _ in ReportTestService.record(a.id,restroom: restroom,draft: form.draft) }
        await store.load(user: a); precondition(store.records.count == 20 && store.hasMore)
        await store.load(user: a,more: true); precondition(store.records.count == 25 && !store.hasMore)
        let detail = try! await store.detail(id: service.rows[0].id,user: a)
        precondition(detail.userID == a.id)
        let reloaded = MyReportsViewModel(service: service)
        await reloaded.load(user: a); precondition(reloaded.records.count == 20)
        store.didSubmit(saved,restroom: restroom); precondition(store.records.first?.id == saved.id && store.label(for: saved) == restroom.name)
        store.setUser(nil); precondition(store.records.isEmpty && store.label(for: saved) == "Reported restroom")
        store.setUser(b); store.didSubmit(saved,restroom: restroom); precondition(store.records.isEmpty)
        await store.load(user: b); precondition(store.records.isEmpty && store.state == .loaded)
        service.suspendRead = true
        let old = Task { await store.load(user: a) }
        for _ in 0..<1000 { if service.readContinuation != nil { break }; await Task.yield() }
        precondition(service.readContinuation != nil)
        store.setUser(b); service.suspendRead = false; await store.load(user: b)
        service.readContinuation?.resume(returning: [saved]); await old.value
        precondition(store.userID == b.id && store.records.isEmpty)
        service.fail = true; await store.load(user: b)
        guard case .error = store.state else { preconditionFailure("Error must not appear as empty success") }
        service.fail = false; await store.load(user: b); precondition(store.state == .loaded)
        print("PASS: private reports page/reload/detail; confirmed list sync; logout clears rows and labels; B cannot receive stale A state; error/empty/retry distinct")
    }
}
