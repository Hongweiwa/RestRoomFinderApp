import Foundation

enum RestroomSortOption: String, CaseIterable, Identifiable {
    case nearest = "Nearest"
    case highestRated = "Highest Rated"
    case mostReviewed = "Most Reviewed"

    var id: Self { self }
}

/// Local filters for the current result set, independent of the Places search radius.
struct RestroomFilter: Equatable {
    var maximumDistanceMiles: Double?
    var minimumGoogleRating: Double?
    var minimumCleanlinessRating: Double?
    // Ready for confirmed three-state opening data; unavailable in today's live UI.
    var openNowOnly = false
    var sortOption: RestroomSortOption = .nearest

    var activeCount: Int {
        (maximumDistanceMiles == nil ? 0 : 1) + (minimumGoogleRating == nil ? 0 : 1) + (openNowOnly ? 1 : 0) + (minimumCleanlinessRating == nil ? 0 : 1)
    }

    func apply(to restrooms: [Restroom], searchText: String = "") -> [Restroom] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return restrooms.filter { restroom in
            if !query.isEmpty && !restroom.name.localizedCaseInsensitiveContains(query) &&
                !restroom.address.localizedCaseInsensitiveContains(query) { return false }
            if let maximumDistanceMiles {
                guard let distance = Self.distance(restroom), distance <= maximumDistanceMiles * 1609.344 else { return false }
            }
            if let minimumGoogleRating {
                guard let rating = Self.rating(restroom), rating >= minimumGoogleRating else { return false }
            }
            if let minimumCleanlinessRating {
                guard let rating = restroom.cleanlinessRating, rating.isFinite,
                      (1...5).contains(rating), rating >= minimumCleanlinessRating else { return false }
            }
            if openNowOnly && (restroom.isOpenNow != true || restroom.businessStatus == .permanentlyClosed ||
                               restroom.businessStatus == .temporarilyClosed) { return false }
            return true
        }.sorted { lhs, rhs in
            switch sortOption {
            case .nearest: break
            case .highestRated:
                let left = Self.rating(lhs) ?? -1
                let right = Self.rating(rhs) ?? -1
                if left != right { return left > right }
            case .mostReviewed:
                let left = lhs.googleUserRatingCount.flatMap { $0 >= 0 ? $0 : nil } ?? -1
                let right = rhs.googleUserRatingCount.flatMap { $0 >= 0 ? $0 : nil } ?? -1
                if left != right { return left > right }
            }
            let left = Self.distance(lhs) ?? .infinity
            let right = Self.distance(rhs) ?? .infinity
            if left != right { return left < right }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func distance(_ restroom: Restroom) -> Double? {
        restroom.distance.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }

    private static func rating(_ restroom: Restroom) -> Double? {
        restroom.googleRating.flatMap { $0.isFinite && (1...5).contains($0) ? $0 : nil }
    }
}
