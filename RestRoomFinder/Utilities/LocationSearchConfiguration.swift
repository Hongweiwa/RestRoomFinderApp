import Foundation

enum LocationSearchConfiguration {
    static let debounce: Duration = .milliseconds(300)
    static let minimumQueryLength = 3
    static let biasRadiusMeters: Double = 50_000
    static let discoveryZoom: Float = 15
}
