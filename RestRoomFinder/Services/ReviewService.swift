import Foundation
import Supabase

@MainActor
final class ReviewService: ReviewServicing {
    private struct Batch: Encodable { let restroom_ids: [UUID]; let place_ids: [String] }
    private struct Page: Encodable {
        var target_restroom: UUID?
        var before_created: String?
        var before_id: UUID?
        let page_size = 21 // One lookahead row; UI displays twenty.
        init(_ id: UUID?, _ cursor: ReviewCursor?) {
            target_restroom = id
            before_created = cursor?.timestamp
            before_id = cursor?.id
        }
    }
    private struct Write: Encodable {
        let overall_rating: Int; let cleanliness_rating: Int; let comment: String?
        enum CodingKeys: String, CodingKey { case overall_rating, cleanliness_rating, comment }
        init(_ draft: ReviewDraft) {
            overall_rating = draft.overallRating; cleanliness_rating = draft.cleanlinessRating; comment = draft.normalizedComment
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(overall_rating, forKey: .overall_rating)
            try c.encode(cleanliness_rating, forKey: .cleanliness_rating)
            // Explicit null clears an existing comment on UPDATE.
            try c.encode(comment, forKey: .comment)
        }
    }
    private struct Insert: Encodable {
        let user_id: UUID; let restroom_id: UUID; let overall_rating: Int; let cleanliness_rating: Int; let comment: String?
    }
    private struct ID: Decodable { let id: UUID }

    func summaries(for restrooms: [Restroom]) async throws -> [RestroomRatingSummary] {
        guard !restrooms.isEmpty else { return [] }
        do {
            let client = try SupabaseManager.shared.client()
            var result: [RestroomRatingSummary] = []
            for start in stride(from: 0, to: restrooms.count, by: 100) {
                let slice = restrooms[start..<min(start + 100, restrooms.count)]
                let params = Batch(restroom_ids: slice.filter { $0.googlePlaceID == nil }.map(\.id), place_ids: slice.compactMap(\.googlePlaceID))
                let rows: [RestroomRatingSummary] = try await client.rpc("restroom_rating_summaries", params: params).execute().value
                result += rows
            }
            return result
        } catch { throw readable(error) }
    }
    func reviews(restroomID: UUID, before: ReviewCursor?) async throws -> [RestroomReview] {
        do { return try await SupabaseManager.shared.client().rpc("restroom_reviews_page", params: Page(restroomID, before)).execute().value }
        catch { throw readable(error) }
    }
    func myReviews(userID: UUID, restroomID: UUID?, before: ReviewCursor?) async throws -> [MyRestroomReview] {
        do {
            let (client, _) = try await RestroomIdentityService.authenticated(userID)
            let result: [MyRestroomReview] = try await client.rpc("my_restroom_reviews", params: Page(restroomID, before)).execute().value
            _ = try await RestroomIdentityService.authenticated(userID)
            return result
        } catch { throw readable(error) }
    }
    func submit(_ draft: ReviewDraft, restroom: Restroom?, existing: RestroomReview?, userID: UUID) async throws {
        if let error = draft.validationError { throw ReviewFailure.validation(error) }
        do {
            let (client, authenticatedID) = try await RestroomIdentityService.authenticated(userID)
            if let existing {
                guard existing.userID == authenticatedID else { throw ReviewFailure.sessionChanged }
                let rows: [ID] = try await client.from("reviews").update(Write(draft))
                    .eq("id", value: existing.id).eq("user_id", value: authenticatedID).select("id").execute().value
                guard rows.count == 1 else { throw ReviewFailure.changed }
            } else {
                guard let restroom else { throw ReviewFailure.changed }
                try await RestroomIdentityService.ensureProfile(client: client, userID: authenticatedID)
                let id = try await RestroomIdentityService.resolve(restroom, client: client)
                _ = try await RestroomIdentityService.authenticated(userID)
                _ = try await client.from("reviews").insert(Insert(user_id: authenticatedID, restroom_id: id,
                    overall_rating: draft.overallRating, cleanliness_rating: draft.cleanlinessRating, comment: draft.normalizedComment)).execute()
            }
            _ = try await RestroomIdentityService.authenticated(userID)
        } catch { throw readable(error) }
    }
    func delete(_ review: RestroomReview, userID: UUID) async throws {
        do {
            let (client, authenticatedID) = try await RestroomIdentityService.authenticated(userID)
            guard review.userID == authenticatedID else { throw ReviewFailure.sessionChanged }
            let rows: [ID] = try await client.from("reviews").delete().eq("id", value: review.id)
                .eq("user_id", value: authenticatedID).select("id").execute().value
            guard rows.count == 1 else { throw ReviewFailure.changed }
            _ = try await RestroomIdentityService.authenticated(userID)
        } catch { throw readable(error) }
    }
    private func readable(_ error: Error) -> ReviewFailure {
        if let known = error as? ReviewFailure { return known }
        if error is RestroomIdentityService.Failure { return .sessionChanged }
        if let code = (error as? PostgrestError)?.code {
            if code == "23505" { return .duplicate }
            if ["PGRST202", "PGRST205", "42P01", "42883"].contains(code) { return .missingSetup }
        }
        return .unavailable
    }
}
