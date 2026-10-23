import CoreLocation
import Foundation

/// Supabase association + app-owned data. Google display fields are never persisted here.
struct FavoriteRecord: Decodable, Equatable, Identifiable {
    let restroomID: UUID
    let restroom: Anchor?
    var id: UUID { restroomID }
    enum CodingKeys: String, CodingKey { case restroomID = "restroom_id", restroom = "restrooms" }
    struct Anchor: Decodable, Equatable {
        let id: UUID
        let googlePlaceID: String?
        let name: String?
        let address: String?
        let latitude: Double?
        let longitude: Double?
        let features: Features?
        enum CodingKeys: String, CodingKey {
            case id, name, address, latitude, longitude
            case googlePlaceID = "google_place_id", features = "restroom_features"
        }
    }
    struct Features: Decodable, Equatable {
        let accessible: Bool?
        let babyChanging: Bool?
        let genderNeutral: Bool?
        let free: Bool?
        enum CodingKeys: String, CodingKey {
            case accessible = "is_accessible", babyChanging = "has_baby_changing"
            case genderNeutral = "is_gender_neutral", free = "is_free"
        }
    }
}

/// Transient Place Details response, with its required provider attributions.
struct SavedPlaceDetails {
    let restroom: Restroom
    var attributions: NSAttributedString? = nil
}

@MainActor
protocol FavoritesServicing {
    func fetchFavorites(expectedUserID: UUID) async throws -> [FavoriteRecord]
    func save(_ restroom: Restroom, expectedUserID: UUID) async throws -> FavoriteRecord
    func remove(_ id: UUID, expectedUserID: UUID) async throws
}

@MainActor
protocol SavedPlaceResolving {
    func fetchSavedPlace(_ placeID: String) async throws -> SavedPlaceDetails
}

enum FavoritesFailure: Error, LocalizedError {
    case sessionChanged, unavailable, network
    case backend(step: String, code: String)
    var errorDescription: String? {
        switch self {
        case let .backend(step, code):
            if code == "PGRST202", step == "profile-recovery" {
                return "Your account profile could not be prepared. The Day 13 profile-recovery migration is missing from this Supabase project or its API schema cache needs refreshing. Reference: \(step)/\(code)."
            }
            if code == "PGRST202", step == "place" {
                return "Saving is not configured in this Supabase project yet. Check the Day 14 favorites migration. Reference: \(step)/\(code)."
            }
            return "Unable to update or load saved restrooms. Please try again. Reference: \(step)/\(code)."
        case .sessionChanged: return "Your account changed. Please reopen Saved Restrooms."
        case .unavailable: return "Unable to update or load saved restrooms. Please try again."
        case .network: return "Unable to connect. Check your connection and try again."
        }
    }
}
