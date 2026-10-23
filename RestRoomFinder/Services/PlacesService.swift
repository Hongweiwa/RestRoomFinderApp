import CoreLocation
import GooglePlaces

@MainActor
final class PlacesService: NearbyRestroomSearching, LocationSearching, SavedPlaceResolving {
    enum ServiceError: Error { case missingAPIKey, invalidSearch, missingPlace }

    func searchNearbyRestrooms(latitude: Double, longitude: Double, radius: Double) async throws -> [Restroom] {
        guard GoogleMapsConfiguration.placesIsConfigured else { throw ServiceError.missingAPIKey }
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(center), radius.isFinite, radius > 0, radius <= 50_000 else {
            throw ServiceError.invalidSearch
        }
        let fields: [GMSPlaceProperty] = [.placeID, .name, .coordinate, .formattedAddress,
                                         .types, .businessStatus, .rating, .userRatingsTotal]
        let request = GMSPlaceSearchNearbyRequest(
            locationRestriction: GMSPlaceCircularLocationOption(center, radius),
            placeProperties: fields.map(\.rawValue))
        request.includedTypes = [NearbySearchConfiguration.includedType]
        request.maxResultCount = NearbySearchConfiguration.maximumResults
        request.rankPreference = .distance
        let response = try await GMSPlacesClient.shared().searchNearby(with: request)
        let records = (response.places ?? []).map { place in
            PlaceRecord(placeID: place.placeID, name: place.name,
                        latitude: place.coordinate.latitude, longitude: place.coordinate.longitude,
                        address: place.formattedAddress, types: place.types ?? [],
                        businessStatus: Self.businessStatus(place.businessStatus),
                        rating: Double(place.rating), ratingCount: Int(place.userRatingsTotal))
        }
        return RestroomPlaceMapper.map(records, from: CLLocation(latitude: latitude, longitude: longitude))
    }

    private var autocompleteSession: (id: UUID, token: GMSAutocompleteSessionToken)?

    private func token(for sessionID: UUID) -> GMSAutocompleteSessionToken {
        if let session = autocompleteSession, session.id == sessionID { return session.token }
        let token = GMSAutocompleteSessionToken()
        autocompleteSession = (sessionID, token)
        return token
    }

    func endAutocompleteSession(_ sessionID: UUID) {
        if autocompleteSession?.id == sessionID { autocompleteSession = nil }
    }

    func autocomplete(query: String, bias: CLLocationCoordinate2D?, sessionID: UUID) async throws -> [LocationPrediction] {
        guard GoogleMapsConfiguration.placesIsConfigured else { throw ServiceError.missingAPIKey }
        let filter = GMSAutocompleteFilter()
        if let bias, CLLocationCoordinate2DIsValid(bias) {
            filter.locationBias = GMSPlaceCircularLocationOption(bias, LocationSearchConfiguration.biasRadiusMeters)
        }
        // Bias only: no country or place-type restrictions, including for remote cities.
        let request = GMSAutocompleteRequest(query: query)
        request.filter = filter
        request.sessionToken = token(for: sessionID)
        return try await withCheckedThrowingContinuation { continuation in
            GMSPlacesClient.shared().fetchAutocompleteSuggestions(from: request) { suggestions, error in
                if let error { continuation.resume(throwing: error); return }
                let predictions = (suggestions ?? []).compactMap { suggestion -> LocationPrediction? in
                    guard let place = suggestion.placeSuggestion else { return nil }
                    return LocationPrediction(id: place.placeID, primaryText: place.attributedPrimaryText.string,
                                              secondaryText: place.attributedSecondaryText?.string)
                }
                continuation.resume(returning: predictions)
            }
        }
    }

    func resolveLocation(_ prediction: LocationPrediction, sessionID: UUID) async throws -> SearchLocation {
        guard GoogleMapsConfiguration.placesIsConfigured else { throw ServiceError.missingAPIKey }
        // Name/address already came from the prediction. Only fetch the ID and coordinate.
        let fields: [GMSPlaceProperty] = [.placeID, .coordinate]
        let request = GMSFetchPlaceRequest(placeID: prediction.id, placeProperties: fields.map(\.rawValue),
                                          sessionToken: token(for: sessionID))
        return try await withCheckedThrowingContinuation { continuation in
            GMSPlacesClient.shared().fetchPlace(with: request) { place, error in
                if let error { continuation.resume(throwing: error); return }
                guard let place, CLLocationCoordinate2DIsValid(place.coordinate) else {
                    continuation.resume(throwing: ServiceError.missingPlace); return
                }
                continuation.resume(returning: SearchLocation(id: place.placeID ?? prediction.id,
                    name: prediction.primaryText, address: prediction.secondaryText,
                    coordinate: place.coordinate, attributions: place.attributions))
            }
        }
    }

    func fetchSavedPlace(_ placeID: String) async throws -> SavedPlaceDetails {
        guard GoogleMapsConfiguration.placesIsConfigured else { throw ServiceError.missingAPIKey }
        let fields: [GMSPlaceProperty] = [.placeID, .name, .coordinate, .formattedAddress,
                                         .businessStatus, .rating, .userRatingsTotal]
        let request = GMSFetchPlaceRequest(placeID: placeID, placeProperties: fields.map(\.rawValue), sessionToken: nil)
        return try await withCheckedThrowingContinuation { continuation in
            GMSPlacesClient.shared().fetchPlace(with: request) { place, error in
                if let error { continuation.resume(throwing: error); return }
                guard let place else { continuation.resume(throwing: ServiceError.missingPlace); return }
                let record = PlaceRecord(placeID: placeID, name: place.name,
                    latitude: place.coordinate.latitude, longitude: place.coordinate.longitude,
                    address: place.formattedAddress, businessStatus: Self.businessStatus(place.businessStatus),
                    rating: Double(place.rating), ratingCount: Int(place.userRatingsTotal))
                guard var restroom = RestroomPlaceMapper.map([record], from: CLLocation(latitude: 0, longitude: 0)).first else {
                    continuation.resume(throwing: ServiceError.missingPlace); return
                }
                restroom.distance = nil
                continuation.resume(returning: SavedPlaceDetails(restroom: restroom, attributions: place.attributions))
            }
        }
    }

    private static func businessStatus(_ status: GMSPlacesBusinessStatus) -> Restroom.BusinessStatus? {
        switch status {
        case .operational: return .operational
        case .closedTemporarily: return .temporarilyClosed
        case .closedPermanently: return .permanentlyClosed
        default: return nil
        }
    }
}
