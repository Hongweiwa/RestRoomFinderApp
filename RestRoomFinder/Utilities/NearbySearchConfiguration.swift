import Foundation

enum NearbySearchConfiguration {
    static let radiusMeters: Double = 1_500
    static let duplicateDistanceMeters: Double = 50
    static let duplicateInterval: TimeInterval = 60
    static let includedType = "public_bathroom"
    static let maximumResults = 20
}
