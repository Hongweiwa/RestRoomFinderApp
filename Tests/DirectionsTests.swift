import CoreLocation
import Foundation
import MapKit

@MainActor
private final class FakeNavigationOpener: NavigationAppOpening {
    var isGoogleMapsInstalled = false
    var appleResult = true
    var urlResults: [Bool] = []
    var urls: [URL] = []
    var items: [MKMapItem] = []
    var modes: [TravelMode] = []

    func openAppleMaps(item: MKMapItem, mode: TravelMode) async -> Bool {
        items.append(item)
        modes.append(mode)
        return appleResult
    }
    func openURL(_ url: URL) async -> Bool {
        urls.append(url)
        return urlResults.isEmpty ? true : urlResults.removeFirst()
    }
}

@MainActor
enum DirectionsTests {
    static func run() async {
        let opener = FakeNavigationOpener()
        let service = DirectionsService(opener: opener)
        let a = restroom("Park A", latitude: 42.3551, longitude: -71.0656)
        let b = restroom("Station B", latitude: 40.7536, longitude: -73.9832)
        do {
            try await service.open(.appleMaps, restroom: a)
            try await service.open(.appleMaps, restroom: b, mode: .driving)
        } catch { preconditionFailure("Valid Apple routes failed: \(error)") }
        precondition(opener.items.count == 2 && opener.modes == [.walking, .driving])
        precondition(opener.items[0].name == a.name && opener.items[1].name == b.name)
        for (item, destination) in zip(opener.items, [a, b]) {
            let coordinate: CLLocationCoordinate2D
            if #available(macOS 26.0, iOS 26.0, *) { coordinate = item.location.coordinate }
            else { coordinate = item.placemark.coordinate }
            precondition(coordinate.latitude == destination.latitude)
            precondition(coordinate.longitude == destination.longitude)
            precondition(!item.isCurrentLocation, "Destination must not be the current user or search center")
        }
        precondition(TravelMode.walking.appleDirectionsMode == MKLaunchOptionsDirectionsModeWalking)
        precondition(TravelMode.driving.appleDirectionsMode == MKLaunchOptionsDirectionsModeDriving)

        for mode in TravelMode.allCases {
            opener.isGoogleMapsInstalled = true
            opener.urls = []
            do { try await service.open(.googleMaps, restroom: a, mode: mode) }
            catch { preconditionFailure("Google app failed") }
            precondition(opener.urls.count == 1 && opener.urls[0].scheme == "comgooglemaps")
            let app = parameters(opener.urls[0])
            precondition(app["daddr"] == "42.3551,-71.0656" && app["directionsmode"] == mode.rawValue)
            precondition(app["saddr"] == nil)

            opener.isGoogleMapsInstalled = false
            opener.urls = []
            do { try await service.open(.googleMaps, restroom: b, mode: mode) }
            catch { preconditionFailure("Google web failed") }
            precondition(opener.urls.count == 1 && opener.urls[0].host == "www.google.com")
            let web = parameters(opener.urls[0])
            precondition(web["destination"] == "40.7536,-73.9832" && web["travelmode"] == mode.rawValue)
            precondition(web["api"] == "1" && web["origin"] == nil)
        }
        opener.isGoogleMapsInstalled = true
        opener.urls = []
        opener.urlResults = [false, true]
        do { try await service.open(.googleMaps, restroom: a) }
        catch { preconditionFailure("App failure must fall back to web") }
        precondition(opener.urls.map(\.scheme) == ["comgooglemaps", "https"])

        opener.urlResults = [false, false]
        do {
            try await service.open(.googleMaps, restroom: a)
            preconditionFailure("Expected Google failure")
        } catch DirectionsService.Failure.googleMapsUnavailable {} catch { preconditionFailure("Wrong failure") }
        opener.appleResult = false
        do {
            try await service.open(.appleMaps, restroom: a)
            preconditionFailure("Expected Apple failure")
        } catch DirectionsService.Failure.appleMapsUnavailable {} catch { preconditionFailure("Wrong failure") }

        let count = opener.items.count + opener.urls.count
        for coordinate in [(91.0, 0.0), (-91, 0), (0, 181), (0, -181), (.nan, 0), (0, .infinity)] {
            let invalid = restroom("Invalid", latitude: coordinate.0, longitude: coordinate.1)
            precondition(DirectionsService.appleMapsURL(destination: invalid.coordinate) == nil)
            precondition(DirectionsService.googleMapsURL(destination: invalid.coordinate, useApp: true) == nil)
            for app in [DirectionsService.NavigationApp.appleMaps, .googleMaps] {
                do {
                    try await service.open(app, restroom: invalid)
                    preconditionFailure("Expected invalid destination")
                } catch DirectionsService.Failure.invalidDestination {} catch { preconditionFailure("Wrong failure") }
            }
        }
        precondition(opener.items.count + opener.urls.count == count, "Invalid data must not launch anything")
        for coordinate in [(90.0, 180.0), (-90, -180), (0, 0)] {
            precondition(DirectionsService.isValid(CLLocationCoordinate2D(latitude: coordinate.0, longitude: coordinate.1)))
        }
        let unnamed = restroom(" \n ", latitude: 42, longitude: -71)
        guard let unnamedItem = DirectionsService.mapItem(for: unnamed) else { preconditionFailure("Name and Google ID are optional") }
        precondition(unnamedItem.name != "Public restroom" && unnamedItem.name != unnamed.name,
                     "Leave missing names to Maps, which may use a coordinate label")
        print("PASS: navigation destinations A/B, native Apple names/modes, Google app/web fallback, opening failures, coordinate validation, missing name/ID, no fixed origin")
    }

    private static func parameters(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    private static func restroom(_ name: String, latitude: Double, longitude: Double) -> Restroom {
        Restroom(id: UUID(), name: name, latitude: latitude, longitude: longitude, address: "",
                 cleanlinessRating: nil, overallRating: nil, reviewCount: nil, distance: nil,
                 openingHours: nil, accessibility: nil, babyChangingStation: nil, genderNeutral: nil,
                 free: nil, imageName: "mappin")
    }
}
