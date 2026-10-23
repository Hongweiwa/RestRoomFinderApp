import MapKit

enum TravelMode: String, CaseIterable, Identifiable {
    case walking, driving

    var id: Self { self }
    var title: String { self == .walking ? "Walking" : "Driving" }
    var appleDirectionsMode: String {
        self == .walking ? MKLaunchOptionsDirectionsModeWalking : MKLaunchOptionsDirectionsModeDriving
    }
    var appleURLFlag: String { self == .walking ? "w" : "d" }
}
