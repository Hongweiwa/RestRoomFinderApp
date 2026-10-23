import Foundation

struct RestroomReview: Decodable, Equatable, Identifiable {
    let id: UUID
    let userID: UUID? // Account deletion can remove authorship without deleting community content.
    let restroomID: UUID
    var overallRating: Int
    var cleanlinessRating: Int? // Historical rows can be unknown; every new submission requires this.
    var comment: String?
    let createdAt: Date
    var updatedAt: Date
    var cursorTimestamp: String? = nil
    var reviewerName: String { "RestRoom Finder User" }
    enum CodingKeys: String, CodingKey {
        case id, comment
        case userID = "user_id", restroomID = "restroom_id", overallRating = "overall_rating"
        case cleanlinessRating = "cleanliness_rating", createdAt = "created_at", updatedAt = "updated_at"
    }
    init(id: UUID, userID: UUID?, restroomID: UUID, overallRating: Int, cleanlinessRating: Int?, comment: String?, createdAt: Date, updatedAt: Date) {
        self.id = id; self.userID = userID; self.restroomID = restroomID; self.overallRating = overallRating
        self.cleanlinessRating = cleanlinessRating; self.comment = comment; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); userID = try c.decodeIfPresent(UUID.self, forKey: .userID)
        restroomID = try c.decode(UUID.self, forKey: .restroomID)
        overallRating = try c.decode(Int.self, forKey: .overallRating)
        cleanlinessRating = try c.decodeIfPresent(Int.self, forKey: .cleanlinessRating)
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
        createdAt = try c.decode(Date.self, forKey: .createdAt); updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        // Preserve PostgreSQL microseconds verbatim for keyset paging; UI uses localized Dates.
        cursorTimestamp = try c.decode(String.self, forKey: .createdAt)
    }

}

struct RestroomRatingSummary: Decodable, Equatable {
    let restroomID: UUID
    let googlePlaceID: String?
    let overallRating: Double?
    let cleanlinessRating: Double?
    let reviewCount: Int
    enum CodingKeys: String, CodingKey {
        case restroomID = "restroom_id", googlePlaceID = "google_place_id", overallRating = "overall_rating"
        case cleanlinessRating = "cleanliness_rating", reviewCount = "review_count"
    }
    var countDescription: String { "\(reviewCount) restroom \(reviewCount == 1 ? "review" : "reviews")" }
    var key: String { googlePlaceID.map { "google:\($0)" } ?? restroomID.uuidString }
}

struct MyRestroomReview: Decodable, Equatable, Identifiable {
    let review: RestroomReview
    let restroom: FavoriteRecord.Anchor?
    var id: UUID { review.id }
}

struct ReviewDraft: Equatable {
    var overallRating = 0
    var cleanlinessRating = 0
    var comment = ""
    init(review: RestroomReview? = nil) {
        overallRating = review?.overallRating ?? 0
        cleanlinessRating = review?.cleanlinessRating ?? 0
        comment = review?.comment ?? ""
    }
    var normalizedComment: String? {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    var validationError: String? {
        guard (1...5).contains(overallRating), (1...5).contains(cleanlinessRating) else {
            return "Choose both an overall rating and a cleanliness rating."
        }
        guard (normalizedComment?.unicodeScalars.count ?? 0) <= 1000 else { return "Use 1,000 characters or fewer." }
        return nil
    }
}

struct ReviewCursor: Equatable {
    let createdAt: Date
    let id: UUID
    let timestamp: String
    init(_ review: RestroomReview) {
        createdAt = review.createdAt; id = review.id
        timestamp = review.cursorTimestamp ?? ISO8601DateFormatter.string(from: review.createdAt,
            timeZone: TimeZone(secondsFromGMT: 0)!, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
    }
}

@MainActor
protocol ReviewServicing {
    func summaries(for restrooms: [Restroom]) async throws -> [RestroomRatingSummary]
    func reviews(restroomID: UUID, before: ReviewCursor?) async throws -> [RestroomReview]
    func myReviews(userID: UUID, restroomID: UUID?, before: ReviewCursor?) async throws -> [MyRestroomReview]
    func submit(_ draft: ReviewDraft, restroom: Restroom?, existing: RestroomReview?, userID: UUID) async throws
    func delete(_ review: RestroomReview, userID: UUID) async throws
}

enum ReviewFailure: Error, LocalizedError {
    case sessionChanged, duplicate, unavailable, missingSetup, validation(String), changed
    var errorDescription: String? {
        switch self {
        case .sessionChanged: return "Your account changed. Please sign in again before reviewing."
        case .duplicate: return "You already reviewed this restroom. Refresh the reviews and choose Edit Your Review."
        case .unavailable: return "Unable to load or save reviews. Check your connection and try again."
        case .missingSetup: return "Reviews are not configured in this Supabase project yet. Apply the Day 13–15 migrations and try again."
        case .validation(let message): return message
        case .changed: return "This review is no longer available to edit. Refresh and try again."
        }
    }
}

extension Restroom {
    var reviewKey: String { googlePlaceID.map { "google:\($0)" } ?? id.uuidString }
    func withRatings(_ summary: RestroomRatingSummary?) -> Restroom {
        var result = self
        result.overallRating = summary?.overallRating
        result.cleanlinessRating = summary?.cleanlinessRating
        result.reviewCount = summary?.reviewCount ?? 0
        return result
    }
}
