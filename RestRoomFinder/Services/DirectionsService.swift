import CoreLocation
import Foundation
import MapKit

/// Platform boundary, injectable so failure and fallback paths can be tested without opening apps.
@MainActor
protocol NavigationAppOpening {
    var isGoogleMapsInstalled: Bool { get }
    func openAppleMaps(item: MKMapItem, mode: TravelMode) async -> Bool
    func openURL(_ url: URL) async -> Bool
}

@MainActor
struct DirectionsService {
    enum NavigationApp { case appleMaps, googleMaps }
    enum Failure: LocalizedError {
        case invalidDestination, appleMapsUnavailable, googleMapsUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidDestination: return "Directions are currently unavailable for this restroom."
            case .appleMapsUnavailable: return "Couldn't open Apple Maps. Try again or choose Google Maps."
            case .googleMapsUnavailable: return "Couldn't open Google Maps or its website. Try again or choose Apple Maps."
            }
        }
    }

    let opener: any NavigationAppOpening
    var isGoogleMapsInstalled: Bool { opener.isGoogleMapsInstalled }

    /// Uses the passed restroom snapshot, never global selection, search center or a fixed origin.
    func open(_ app: NavigationApp, restroom: Restroom, mode: TravelMode = .walking) async throws {
        guard let item = Self.mapItem(for: restroom) else { throw Failure.invalidDestination }
        switch app {
        case .appleMaps:
            guard await opener.openAppleMaps(item: item, mode: mode) else { throw Failure.appleMapsUnavailable }
        case .googleMaps:
            if opener.isGoogleMapsInstalled,
               let url = Self.googleMapsURL(destination: restroom.coordinate, mode: mode, useApp: true),
               await opener.openURL(url) { return }
            guard let url = Self.googleMapsURL(destination: restroom.coordinate, mode: mode, useApp: false),
                  await opener.openURL(url) else { throw Failure.googleMapsUnavailable }
        }
    }

    nonisolated static func isValid(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude.isFinite && coordinate.longitude.isFinite && CLLocationCoordinate2DIsValid(coordinate)
    }

    nonisolated static func mapItem(for restroom: Restroom) -> MKMapItem? {
        guard isValid(restroom.coordinate) else { return nil }
        let item: MKMapItem
        if #available(iOS 26.0, macOS 26.0, *) {
            item = MKMapItem(location: CLLocation(latitude: restroom.latitude, longitude: restroom.longitude), address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: restroom.coordinate))
        }
        let name = restroom.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { item.name = name }
        return item
    }

    /// Retained for sharing a directions link. Launching Apple Maps uses MKMapItem instead.
    nonisolated static func appleMapsURL(destination: CLLocationCoordinate2D, mode: TravelMode = .walking) -> URL? {
        guard isValid(destination) else { return nil }
        var url = URLComponents()
        url.scheme = "https"
        url.host = "maps.apple.com"
        url.path = "/"
        url.queryItems = [
            URLQueryItem(name: "daddr", value: "\(destination.latitude),\(destination.longitude)"),
            URLQueryItem(name: "dirflg", value: mode.appleURLFlag)
        ]
        return url.url
    }

    nonisolated static func googleMapsURL(destination: CLLocationCoordinate2D, mode: TravelMode = .walking, useApp: Bool) -> URL? {
        guard isValid(destination) else { return nil }
        let coordinate = "\(destination.latitude),\(destination.longitude)"
        var url = URLComponents()
        url.scheme = useApp ? "comgooglemaps" : "https"
        url.host = useApp ? "" : "www.google.com"
        url.path = useApp ? "" : "/maps/dir/"
        url.queryItems = useApp ? [
            URLQueryItem(name: "daddr", value: coordinate),
            URLQueryItem(name: "directionsmode", value: mode.rawValue)
        ] : [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: coordinate),
            URLQueryItem(name: "travelmode", value: mode.rawValue)
        ]
        // No origin: the external app/browser handles current location and its permissions.
        return url.url
    }
}
