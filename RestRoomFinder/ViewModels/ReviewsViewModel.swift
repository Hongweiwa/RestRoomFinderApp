import Combine
import Foundation

@MainActor
final class ReviewsViewModel: ObservableObject {
    enum State: Equatable { case idle, loading, loaded, error(String) }
    struct Entry {
        var state: State = .idle
        var rows: [RestroomReview] = []
        var own: RestroomReview?
        var cursor: ReviewCursor?
        var hasMore = false
        var paging = false
        var pageError: String?
    }
    @Published private(set) var entries: [String: Entry] = [:]
    @Published private(set) var summaries: [String: RestroomRatingSummary] = [:]
    @Published private(set) var summaryError: String?
    @Published private(set) var myRows: [MyRestroomReview] = []
    @Published private(set) var myState: State = .idle
    @Published private(set) var myHasMore = false
    @Published private(set) var myPaging = false
    @Published private(set) var myPageError: String?
    @Published private(set) var isSaving = false
    @Published private(set) var userID: UUID?
    @Published private(set) var changeRevision = 0
    @Published private(set) var knownPlaces: [String: SavedPlaceDetails] = [:]
    private let service: any ReviewServicing
    private let places: any SavedPlaceResolving
    private var generation = 0
    private var requests: [String: Int] = [:]
    private var summaryRequest = 0
    private var myRequest = 0
    private var myCursor: ReviewCursor?

    init(service: any ReviewServicing, places: any SavedPlaceResolving) {
        self.service = service; self.places = places
    }
    func setUser(_ user: AuthUser?) {
        guard userID != user?.id else { return }
        userID = user?.id
        isSaving = false
        knownPlaces = [:]
        invalidate()
    }
    private func invalidate() {
        generation += 1; summaryRequest += 1; myRequest += 1
        entries = [:]; requests = [:]; summaries = [:]; summaryError = nil
        myRows = []; myState = .idle; myHasMore = false; myPaging = false; myPageError = nil; myCursor = nil
        changeRevision += 1
    }
    func register(_ restrooms: [Restroom]) {
        for restroom in restrooms where knownPlaces[restroom.reviewKey] == nil {
            knownPlaces[restroom.reviewKey] = SavedPlaceDetails(restroom: restroom)
        }
    }
    func refreshSummaries(for restrooms: [Restroom]) async {
        guard !restrooms.isEmpty else { return }
        register(restrooms)
        summaryRequest += 1
        let request = summaryRequest, account = generation
        do {
            let rows = try await service.summaries(for: restrooms)
            guard request == summaryRequest, account == generation, !Task.isCancelled else { return }
            for restroom in restrooms { summaries[restroom.reviewKey] = nil }
            for row in rows { summaries[row.key] = row }
            summaryError = nil
        } catch {
            guard request == summaryRequest, account == generation, !Task.isCancelled else { return }
            for restroom in restrooms { summaries[restroom.reviewKey] = nil }
            summaryError = "Community ratings unavailable. Cleanliness filters exclude unverified scores."
        }
    }
    func entry(for restroom: Restroom) -> Entry { entries[restroom.reviewKey] ?? Entry() }
    func load(_ restroom: Restroom) async {
        let key = restroom.reviewKey, account = generation, user = userID
        register([restroom])
        requests[key, default: 0] += 1
        let request = requests[key]
        entries[key] = Entry(state: .loading)
        do {
            let summary = try await service.summaries(for: [restroom]).first
            var rows: [RestroomReview] = [], own: RestroomReview?
            if let id = summary?.restroomID {
                rows = try await service.reviews(restroomID: id, before: nil)
                if let user { own = try await service.myReviews(userID: user, restroomID: id, before: nil).first?.review }
            }
            guard account == generation, requests[key] == request, !Task.isCancelled else { return }
            summaries[key] = summary
            let visible = Array(rows.prefix(20))
            entries[key] = Entry(state: .loaded, rows: visible, own: own,
                cursor: visible.last.map(ReviewCursor.init), hasMore: rows.count > 20)
        } catch {
            guard account == generation, requests[key] == request, !Task.isCancelled else { return }
            entries[key] = Entry(state: .error(Self.message(error)))
        }
    }
    func loadMore(_ restroom: Restroom) async {
        let key = restroom.reviewKey, account = generation, request = requests[restroom.reviewKey]
        guard var entry = entries[key], entry.state == .loaded, entry.hasMore, !entry.paging,
              let id = summaries[key]?.restroomID else { return }
        entry.paging = true; entry.pageError = nil; entries[key] = entry
        do {
            let page = try await service.reviews(restroomID: id, before: entry.cursor)
            guard account == generation, request == requests[key], !Task.isCancelled else { return }
            let rows = Array(page.prefix(20)), existing = Set(entry.rows.map(\.id))
            entry.rows += rows.filter { !existing.contains($0.id) }
            entry.cursor = rows.last.map(ReviewCursor.init); entry.hasMore = page.count > 20
        } catch { entry.pageError = Self.message(error) }
        guard account == generation, request == requests[key] else { return }
        entry.paging = false; entries[key] = entry
    }
    func loadMine(more: Bool = false) async {
        guard let user = userID, !myPaging else { return }
        if more && !myHasMore { return }
        let account = generation
        myRequest += 1
        let request = myRequest
        if more { myPaging = true; myPageError = nil } else { myState = .loading }
        do {
            let page = try await service.myReviews(userID: user, restroomID: nil, before: more ? myCursor : nil)
            guard account == generation, request == myRequest, !Task.isCancelled else { return }
            let visible = Array(page.prefix(20)), existing = Set(myRows.map(\.id))
            myRows = more ? myRows + visible.filter { !existing.contains($0.id) } : visible
            myCursor = visible.last.map { ReviewCursor($0.review) }; myHasMore = page.count > 20
            myState = .loaded
        } catch {
            guard account == generation, request == myRequest, !Task.isCancelled else { return }
            if more { myPageError = Self.message(error) } else { myState = .error(Self.message(error)) }
        }
        if account == generation, request == myRequest { myPaging = false }
    }
    func submit(_ draft: ReviewDraft, restroom: Restroom?, existing: RestroomReview?, expectedUserID: UUID) async -> String? {
        if let error = draft.validationError { return error }
        guard userID == expectedUserID else { return ReviewFailure.sessionChanged.localizedDescription }
        guard !isSaving else { return "A review is already being saved." }
        if let existing, existing.userID != expectedUserID { return ReviewFailure.sessionChanged.localizedDescription }
        isSaving = true
        let account = generation
        do {
            try await service.submit(draft, restroom: restroom, existing: existing, userID: expectedUserID)
            guard account == generation else { return ReviewFailure.sessionChanged.localizedDescription }
            isSaving = false; invalidate()
            return nil
        } catch {
            guard account == generation else { return ReviewFailure.sessionChanged.localizedDescription }
            isSaving = false
            return Self.message(error)
        }
    }
    func delete(_ review: RestroomReview, expectedUserID: UUID) async -> String? {
        guard userID == expectedUserID, review.userID == expectedUserID else { return ReviewFailure.sessionChanged.localizedDescription }
        guard !isSaving else { return "A review is already being updated." }
        isSaving = true
        let account = generation
        do {
            try await service.delete(review, userID: expectedUserID)
            guard account == generation else { return ReviewFailure.sessionChanged.localizedDescription }
            isSaving = false; invalidate()
            return nil
        } catch {
            guard account == generation else { return ReviewFailure.sessionChanged.localizedDescription }
            isSaving = false; return Self.message(error)
        }
    }
    func place(for row: MyRestroomReview) -> SavedPlaceDetails? {
        let key = row.restroom?.googlePlaceID.map { "google:\($0)" } ?? row.review.restroomID.uuidString
        return knownPlaces[key]
    }
    func openPlace(for row: MyRestroomReview) async throws -> SavedPlaceDetails {
        if let existing = place(for: row) { return existing }
        let account = generation
        guard let anchor = row.restroom else { throw ReviewFailure.changed }
        let result: SavedPlaceDetails
        if let placeID = anchor.googlePlaceID { result = try await places.fetchSavedPlace(placeID) }
        else {
            guard let name = anchor.name, let lat = anchor.latitude, let lon = anchor.longitude else { throw ReviewFailure.changed }
            result = SavedPlaceDetails(restroom: Restroom(id: anchor.id, name: name, latitude: lat, longitude: lon,
                address: anchor.address ?? "Address unavailable", cleanlinessRating: nil, overallRating: nil, reviewCount: nil,
                distance: nil, openingHours: nil, accessibility: nil, babyChangingStation: nil, genderNeutral: nil, free: nil, imageName: "toilet"))
        }
        guard account == generation else { throw ReviewFailure.sessionChanged }
        knownPlaces[result.restroom.reviewKey] = result
        return result
    }
    static func message(_ error: Error) -> String { (error as? ReviewFailure)?.localizedDescription ?? ReviewFailure.unavailable.localizedDescription }
}
