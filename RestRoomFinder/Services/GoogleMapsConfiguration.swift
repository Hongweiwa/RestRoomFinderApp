import Foundation
import GoogleMaps
import GooglePlaces

/// Both SDKs share the existing build configuration; views never own the key.
@MainActor
enum GoogleMapsConfiguration {
    private static let apiKey: String? = {
        guard let rawKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String else { return nil }
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != "YOUR_API_KEY", !key.contains("$(") else { return nil }
        return key
    }()
    static let isConfigured: Bool = {
        guard let apiKey else { return false }
        return GMSServices.provideAPIKey(apiKey)
    }()
    static let placesIsConfigured: Bool = {
        guard let apiKey else { return false }
        return GMSPlacesClient.provideAPIKey(apiKey)
    }()
}
