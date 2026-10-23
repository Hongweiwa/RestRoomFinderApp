import CoreLocation
import Foundation

struct Restroom: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String
    /// RestRoom Finder community ratings use a 1–5 scale; nil means unknown.
    var cleanlinessRating: Double?
    var overallRating: Double?
    var reviewCount: Int?
    /// Meters from the user; nil until their location is available.
    var distance: CLLocationDistance?
    let openingHours: String?
    /// Whether the restroom supports wheelchair access.
    let accessibility: Bool?
    let babyChangingStation: Bool?
    let genderNeutral: Bool?
    let free: Bool?
    /// An SF Symbol name for the development scaffold.
    let imageName: String

    /// Development status; not inferred from display-only opening hours.
    var isOpenNow: Bool? = nil

    /// Google identity is retained verbatim; UUID remains for existing app routes.
    var googlePlaceID: String? = nil
    var placeTypes: [String] = []
    var businessStatus: BusinessStatus? = nil
    /// Google ratings are distinct from RestRoom Finder reviews and cleanliness.
    var googleRating: Double? = nil
    var googleUserRatingCount: Int? = nil

    enum BusinessStatus: String, Codable {
        case operational, temporarilyClosed, permanentlyClosed
    }

    var accessibilityDescription: String {
        switch accessibility {
        case true: return "Accessible"
        case false: return "No step-free access"
        default: return "Accessibility unknown"
        }
    }

    var availabilityDescription: String {
        switch businessStatus {
        case .permanentlyClosed: return "Permanently closed"
        case .temporarilyClosed: return "Temporarily closed"
        default:
            if isOpenNow == true { return "Open now" }
            if let openingHours { return openingHours }
            if isOpenNow == false { return "Closed now" }
            return "Hours unknown"
        }
    }

    var distanceDescription: String {
        guard let distance, distance.isFinite, distance >= 0 else { return "Distance unavailable" }
        return "\((distance / 1609.344).formatted(.number.precision(.fractionLength(1)))) mi away"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
