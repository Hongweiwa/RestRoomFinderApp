import CoreLocation
import Foundation

/// Geographic predictions and destinations are separate from restroom results.
struct LocationPrediction: Identifiable, Equatable {
    let id: String
    let primaryText: String
    let secondaryText: String?
}

struct SearchLocation: Identifiable {
    let id: String
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D
    var attributions: NSAttributedString? = nil
}
