/// Small data boundary; a future data source can replace the sample service.
protocol RestroomService {
    func fetchRestrooms() -> [Restroom]
}

/// Async discovery boundary used by the map; independent of Google's SDK types.
@MainActor
protocol NearbyRestroomSearching {
    func searchNearbyRestrooms(latitude: Double, longitude: Double, radius: Double) async throws -> [Restroom]
}

struct SampleRestroomService: RestroomService {
    func fetchRestrooms() -> [Restroom] {
        SampleRestrooms.all
    }
}
