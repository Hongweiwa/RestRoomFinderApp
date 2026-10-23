import CoreLocation
import Foundation

/// Implemented by the existing PlacesService; SDK types stay at the service boundary.
@MainActor
protocol LocationSearching {
    func autocomplete(query: String, bias: CLLocationCoordinate2D?, sessionID: UUID) async throws -> [LocationPrediction]
    func resolveLocation(_ prediction: LocationPrediction, sessionID: UUID) async throws -> SearchLocation
    func endAutocompleteSession(_ sessionID: UUID)
}
