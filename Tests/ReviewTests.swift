import Foundation

@MainActor
private final class ReviewTestService: ReviewServicing {
    var summaryRows: [RestroomRatingSummary] = []
    var page: [RestroomReview] = []
    var own: [MyRestroomReview] = []
    var calls = 0; var mutations = 0; var deletes = 0
    var fail = false
    var pending: CheckedContinuation<Void, Error>?
    var suspend = false
    var cursors: [ReviewCursor?] = []
    func summaries(for restrooms: [Restroom]) async throws -> [RestroomRatingSummary] {
        calls += 1
        if fail { throw ReviewFailure.unavailable }
        return summaryRows
    }
    func reviews(restroomID: UUID, before: ReviewCursor?) async throws -> [RestroomReview] {
        cursors.append(before)
        if fail { throw ReviewFailure.unavailable }
        return page
    }
    func myReviews(userID: UUID, restroomID: UUID?, before: ReviewCursor?) async throws -> [MyRestroomReview] {
        if fail { throw ReviewFailure.unavailable }
        return own.filter { $0.review.userID == userID }
    }
    func submit(_ draft: ReviewDraft, restroom: Restroom?, existing: RestroomReview?, userID: UUID) async throws {
        mutations += 1
        if suspend { try await withCheckedThrowingContinuation { pending = $0 } }
        if fail { throw ReviewFailure.unavailable }
    }
    func delete(_ review: RestroomReview, userID: UUID) async throws { deletes += 1; if fail { throw ReviewFailure.unavailable } }
}
@MainActor
private final class ReviewTestPlaces: SavedPlaceResolving {
    var calls = 0
    func fetchSavedPlace(_ placeID: String) async throws -> SavedPlaceDetails { calls += 1; throw ReviewFailure.unavailable }
}
@MainActor
enum ReviewTests {
    static func run() async {
        var draft = ReviewDraft()
        precondition(draft.validationError != nil)
        draft.overallRating = 4; draft.cleanlinessRating = 5; draft.comment = " \n Very clean.  \n"
        precondition(draft.validationError == nil && draft.normalizedComment == "Very clean.")
        draft.comment = " \n\t "; precondition(draft.normalizedComment == nil)
        draft.comment = String(repeating: "a", count: 1001); precondition(draft.validationError != nil)
        draft.comment = "Very clean."
        let a = AuthUser(id: UUID(), email: "a@example.com"), b = AuthUser(id: UUID(), email: "b@example.com")
        let service = ReviewTestService(), places = ReviewTestPlaces()
        let vm = ReviewsViewModel(service: service, places: places)
        var restroom = SampleRestrooms.all[0]
        restroom.googlePlaceID = "test-place"; restroom.googleRating = 4.7
        await vm.load(restroom)
        precondition(vm.entry(for: restroom).state == .loaded && vm.entry(for: restroom).rows.isEmpty)
        precondition(vm.summaries.isEmpty && service.mutations == 0 && places.calls == 0)
        let summary = RestroomRatingSummary(restroomID: UUID(), googlePlaceID: "test-place", overallRating: 4.1, cleanlinessRating: 3.4, reviewCount: 18)
        service.summaryRows = [summary]
        await vm.refreshSummaries(for: Array(repeating: restroom, count: 20))
        precondition(service.calls == 2, "Batch summaries once, not once per card")
        let enriched = restroom.withRatings(vm.summaries[restroom.reviewKey])
        precondition(enriched.googleRating == 4.7 && enriched.overallRating == 4.1 && enriched.cleanlinessRating == 3.4 && enriched.reviewCount == 18)
        var filter = RestroomFilter(); filter.minimumCleanlinessRating = 4
        precondition(filter.apply(to: [enriched, restroom.withRatings(nil)]).isEmpty)
        filter.minimumCleanlinessRating = 3
        precondition(filter.apply(to: [enriched, restroom.withRatings(nil)]).count == 1)
        print("PASS: review validation, trimmed comments, unknown cleanliness, Google separation and one batched rating lookup")
        let now = Date()
        func row(_ owner: UUID = a.id) -> RestroomReview {
            RestroomReview(id: UUID(), userID: owner, restroomID: summary.restroomID, overallRating: 4, cleanlinessRating: 5,
                comment: "Very clean.", createdAt: now, updatedAt: now)
        }
        let own = row()
        service.page = (0..<21).map { _ in row(b.id) }
        service.own = [MyRestroomReview(review: own, restroom: nil)]
        vm.setUser(a)
        await vm.load(restroom)
        precondition(vm.entry(for: restroom).rows.count == 20 && vm.entry(for: restroom).hasMore)
        precondition(vm.entry(for: restroom).own?.id == own.id, "Own review must be found even beyond the first public page")
        let lookahead = service.page[20]; service.page = [lookahead]
        await vm.loadMore(restroom)
        precondition(vm.entry(for: restroom).rows.count == 21 && !vm.entry(for: restroom).hasMore)
        precondition(service.cursors.last! != nil)
        await vm.loadMine(); precondition(vm.myRows.count == 1)
        service.fail = true
        let error = await vm.submit(draft, restroom: restroom, existing: own, expectedUserID: a.id)
        precondition(error != nil && !vm.isSaving && vm.myRows.count == 1)
        service.fail = false
        let revision = vm.changeRevision
        let success = await vm.submit(draft, restroom: restroom, existing: own, expectedUserID: a.id)
        precondition(success == nil && vm.changeRevision > revision && vm.entries.isEmpty && vm.summaries.isEmpty)
        precondition(places.calls == 0, "Review writes must not call Google")
        print("PASS: 20-row paging, own review outside public page, failed-write retention and successful aggregate/My Reviews invalidation")
        service.suspend = true
        let task = Task { await vm.submit(draft, restroom: restroom, existing: nil, expectedUserID: a.id) }
        for _ in 0..<1000 { if service.pending != nil { break }; await Task.yield() }
        precondition(service.pending != nil)
        let mutations = service.mutations
        _ = await vm.submit(draft, restroom: restroom, existing: nil, expectedUserID: a.id)
        precondition(service.mutations == mutations)
        vm.setUser(b)
        service.pending?.resume(); _ = await task.value
        precondition(vm.userID == b.id && vm.myRows.isEmpty && !vm.isSaving)
        _ = await vm.delete(own, expectedUserID: b.id)
        precondition(service.deletes == 0)
        service.fail = true
        await vm.load(restroom)
        guard case .error = vm.entry(for: restroom).state else { preconditionFailure("Failure cannot appear as zero reviews") }
        service.fail = false
        await vm.load(restroom)
        precondition(vm.entry(for: restroom).state == .loaded)
        print("PASS: duplicate submission blocked, late A mutation ignored after B login, foreign review deletion rejected, error/retry distinct from empty")
        let json = """
        {"id":"\(UUID())","user_id":null,"restroom_id":"\(UUID())","overall_rating":4,"cleanliness_rating":null,"comment":null,"created_at":"2026-10-15T12:00:00.123456+00:00","updated_at":"2026-10-15T12:00:00.123456+00:00"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: text)!
        }
        let decoded = try! decoder.decode(RestroomReview.self, from: Data(json.utf8))
        precondition(ReviewCursor(decoded).timestamp == "2026-10-15T12:00:00.123456+00:00")
        precondition(decoded.userID == nil && decoded.cleanlinessRating == nil && decoded.reviewerName == "RestRoom Finder User")
        print("PASS: microsecond paging cursor retained and deleted-author/legacy cleanliness handled without fabricated data")
    }
}
