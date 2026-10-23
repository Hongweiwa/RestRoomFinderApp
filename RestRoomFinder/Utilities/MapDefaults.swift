import MapKit

/// Fallback region for the future map screen when user location is unavailable.
enum MapDefaults {
    static let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7536, longitude: -73.9832),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
}
