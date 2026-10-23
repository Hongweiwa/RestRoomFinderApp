import CoreLocation
import CryptoKit
import Foundation

/// SDK-independent snapshot at the service boundary; also enables fixture tests.
struct PlaceRecord {
    let placeID: String?
    let name: String?
    let latitude: Double
    let longitude: Double
    let address: String?
    var types: [String] = []
    var businessStatus: Restroom.BusinessStatus? = nil
    var rating: Double? = nil
    var ratingCount: Int? = nil
}

enum RestroomPlaceMapper {
    static func map(_ records: [PlaceRecord], from origin: CLLocation) -> [Restroom] {
        var seen = Set<String>()
        let restrooms = records.compactMap { record -> Restroom? in
            guard let placeID = record.placeID, !placeID.isEmpty,
                  CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: record.latitude, longitude: record.longitude)),
                  seen.insert(placeID).inserted else { return nil }
            let name = record.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Restroom(
                id: stableID(for: placeID), name: name.flatMap { $0.isEmpty ? nil : $0 } ?? "Public restroom",
                latitude: record.latitude, longitude: record.longitude,
                address: record.address ?? "Address unavailable",
                cleanlinessRating: nil, overallRating: nil, reviewCount: nil,
                distance: nil, openingHours: nil,
                accessibility: nil, babyChangingStation: nil, genderNeutral: nil, free: nil,
                imageName: "toilet", isOpenNow: nil, googlePlaceID: placeID,
                placeTypes: record.types, businessStatus: record.businessStatus,
                googleRating: record.rating.flatMap { (1...5).contains($0) ? $0 : nil },
                googleUserRatingCount: record.ratingCount.flatMap { $0 > 0 ? $0 : nil }
            )
        }
        return measuring(restrooms, from: origin)
    }

    /// Shared distance calculation used after both searches and actual location changes.
    static func measuring(_ restrooms: [Restroom], from origin: CLLocation?) -> [Restroom] {
        restrooms.map { restroom in
            var result = restroom
            result.distance = origin?.distance(from: CLLocation(latitude: restroom.latitude, longitude: restroom.longitude))
            return result
        }.sorted {
            if $0.distance == $1.distance { return $0.id.uuidString < $1.id.uuidString }
            return ($0.distance ?? .infinity) < ($1.distance ?? .infinity)
        }
    }

    // A deterministic UUID adapter preserves existing UUID-based routes without
    // replacing Google's original ID (which is the deduplication identity).
    private static func stableID(for placeID: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data("google-places:\(placeID)".utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
